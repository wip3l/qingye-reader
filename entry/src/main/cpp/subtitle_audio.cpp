// 听书字幕的音频解码：从本地音频文件里取一段，解成 16 kHz 单声道 float，交给语音识别。
// 只在字幕 Worker 里同步调用，一次最多几十秒音频；用 API 20 的音频解码同步模式，不起回调线程。
#include <napi/native_api.h>
#include <multimedia/player_framework/native_avbuffer.h>
#include <multimedia/player_framework/native_avcodec_audiocodec.h>
#include <multimedia/player_framework/native_avcodec_base.h>
#include <multimedia/player_framework/native_avdemuxer.h>
#include <multimedia/player_framework/native_avformat.h>
#include <multimedia/player_framework/native_avsource.h>

#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fcntl.h>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace {

constexpr int32_t kTargetRate = 16000;
// 一次最多解 60 秒，免得调用方传错参数把内存吃光。
constexpr int64_t kMaxSpanMs = 60000;
// 单次解码的墙钟上限：损坏文件或解码器卡住时放弃这一段。
constexpr int64_t kDeadlineMs = 20000;
constexpr int64_t kQueryTimeoutUs = 20000;

struct Media {
    int fd = -1;
    OH_AVSource *source = nullptr;
    OH_AVDemuxer *demuxer = nullptr;
    OH_AVCodec *codec = nullptr;
    OH_AVFormat *trackFormat = nullptr;
    int32_t track = -1;
    int64_t durationMs = 0;
    std::string mime;

    ~Media()
    {
        if (codec) {
            OH_AudioCodec_Stop(codec);
            OH_AudioCodec_Destroy(codec);
        }
        if (trackFormat) OH_AVFormat_Destroy(trackFormat);
        if (demuxer) OH_AVDemuxer_Destroy(demuxer);
        if (source) OH_AVSource_Destroy(source);
        if (fd >= 0) close(fd);
    }
};

void Require(bool ok, const char *message)
{
    if (!ok) throw std::runtime_error(message);
}

/** 打开文件、找到第一条音轨。只探测时不建解码器。 */
void Open(Media &media, const std::string &path)
{
    media.fd = open(path.c_str(), O_RDONLY);
    Require(media.fd >= 0, "subtitle_open");
    struct stat st {};
    Require(fstat(media.fd, &st) == 0 && st.st_size > 0, "subtitle_open");
    media.source = OH_AVSource_CreateWithFD(media.fd, 0, st.st_size);
    Require(media.source != nullptr, "subtitle_format");

    OH_AVFormat *sourceFormat = OH_AVSource_GetSourceFormat(media.source);
    Require(sourceFormat != nullptr, "subtitle_format");
    int32_t tracks = 0;
    int64_t durationUs = 0;
    OH_AVFormat_GetIntValue(sourceFormat, OH_MD_KEY_TRACK_COUNT, &tracks);
    if (OH_AVFormat_GetLongValue(sourceFormat, OH_MD_KEY_DURATION, &durationUs) && durationUs > 0) {
        media.durationMs = durationUs / 1000;
    }
    OH_AVFormat_Destroy(sourceFormat);

    for (int32_t i = 0; i < tracks && media.track < 0; i++) {
        OH_AVFormat *format = OH_AVSource_GetTrackFormat(media.source, i);
        if (!format) continue;
        int32_t type = -1;
        const char *mime = nullptr;
        if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_TRACK_TYPE, &type) && type == MEDIA_TYPE_AUD &&
            OH_AVFormat_GetStringValue(format, OH_MD_KEY_CODEC_MIME, &mime) && mime) {
            media.track = i;
            media.mime = mime;
            media.trackFormat = format;
            if (media.durationMs <= 0 && OH_AVFormat_GetLongValue(format, OH_MD_KEY_DURATION, &durationUs) &&
                durationUs > 0) {
                media.durationMs = durationUs / 1000;
            }
        } else {
            OH_AVFormat_Destroy(format);
        }
    }
    Require(media.track >= 0, "subtitle_no_audio");
}

struct PcmFormat {
    int32_t rate = 0;
    int32_t channels = 0;
    int32_t sampleFormat = SAMPLE_S16LE;
};

void ReadOutputFormat(OH_AVCodec *codec, PcmFormat &pcm)
{
    OH_AVFormat *format = OH_AudioCodec_GetOutputDescription(codec);
    if (!format) return;
    int32_t value = 0;
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_AUD_SAMPLE_RATE, &value) && value > 0) pcm.rate = value;
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_AUD_CHANNEL_COUNT, &value) && value > 0) pcm.channels = value;
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_AUDIO_SAMPLE_FORMAT, &value)) pcm.sampleFormat = value;
    OH_AVFormat_Destroy(format);
}

int32_t BytesPerSample(int32_t sampleFormat)
{
    switch (sampleFormat) {
        case SAMPLE_U8: return 1;
        case SAMPLE_S16LE: return 2;
        case SAMPLE_S24LE: return 3;
        case SAMPLE_S32LE: return 4;
        case SAMPLE_F32LE: return 4;
        default: return 0;
    }
}

float SampleAt(const uint8_t *p, int32_t sampleFormat)
{
    switch (sampleFormat) {
        case SAMPLE_U8: return (static_cast<int32_t>(p[0]) - 128) / 128.0f;
        case SAMPLE_S16LE: {
            int16_t v;
            std::memcpy(&v, p, 2);
            return v / 32768.0f;
        }
        case SAMPLE_S24LE: {
            int32_t v = (static_cast<int32_t>(p[2]) << 24) | (static_cast<int32_t>(p[1]) << 16) |
                        (static_cast<int32_t>(p[0]) << 8);
            return static_cast<float>(v / 2147483648.0);
        }
        case SAMPLE_S32LE: {
            int32_t v;
            std::memcpy(&v, p, 4);
            return static_cast<float>(v / 2147483648.0);
        }
        case SAMPLE_F32LE: {
            float v;
            std::memcpy(&v, p, 4);
            return v;
        }
        default: return 0.0f;
    }
}

struct DecodeResult {
    std::vector<float> samples;  // 16 kHz 单声道
    int64_t startMs = 0;
    int64_t durationMs = 0;
};

/** 线性插值重采样到目标采样率（默认 16 kHz）。语音识别用的特征本身就有低通，这里不再额外滤波。 */
std::vector<float> Resample(const std::vector<float> &input, int32_t rate, int32_t targetRate)
{
    if (rate == targetRate || input.empty()) return input;
    const double ratio = static_cast<double>(rate) / targetRate;
    const size_t count = static_cast<size_t>(std::floor((input.size() - 1) / ratio)) + 1;
    std::vector<float> output(count);
    for (size_t i = 0; i < count; i++) {
        const double position = i * ratio;
        const size_t left = static_cast<size_t>(position);
        const size_t right = left + 1 < input.size() ? left + 1 : left;
        const float fraction = static_cast<float>(position - left);
        output[i] = input[left] + (input[right] - input[left]) * fraction;
    }
    return output;
}

DecodeResult Decode(const std::string &path, int64_t startMs, int64_t spanMs, int32_t targetRate)
{
    Media media;
    Open(media, path);
    DecodeResult result;
    result.durationMs = media.durationMs;
    result.startMs = startMs;
    const int64_t endMs = startMs + spanMs;
    if (media.durationMs > 0 && startMs >= media.durationMs) return result;

    media.demuxer = OH_AVDemuxer_CreateWithSource(media.source);
    Require(media.demuxer != nullptr, "subtitle_demux");
    Require(OH_AVDemuxer_SelectTrackByID(media.demuxer, media.track) == AV_ERR_OK, "subtitle_demux");
    // 定位失败（个别格式不支持）就从头解，前面的样本丢掉，只是慢一点。
    if (startMs > 0) OH_AVDemuxer_SeekToTime(media.demuxer, startMs, SEEK_MODE_PREVIOUS_SYNC);

    media.codec = OH_AudioCodec_CreateByMime(media.mime.c_str(), false);
    Require(media.codec != nullptr, "subtitle_codec");
    OH_AVFormat_SetIntValue(media.trackFormat, OH_MD_KEY_ENABLE_SYNC_MODE, 1);
    OH_AVFormat_SetIntValue(media.trackFormat, OH_MD_KEY_AUDIO_SAMPLE_FORMAT, SAMPLE_S16LE);
    Require(OH_AudioCodec_Configure(media.codec, media.trackFormat) == AV_ERR_OK, "subtitle_codec");
    Require(OH_AudioCodec_Prepare(media.codec) == AV_ERR_OK, "subtitle_codec");
    Require(OH_AudioCodec_Start(media.codec) == AV_ERR_OK, "subtitle_codec");

    PcmFormat pcm;
    ReadOutputFormat(media.codec, pcm);
    std::vector<float> mono;
    bool inputDone = false;
    bool outputDone = false;
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(kDeadlineMs);

    while (!outputDone) {
        Require(std::chrono::steady_clock::now() < deadline, "subtitle_timeout");
        if (!inputDone) {
            uint32_t index = 0;
            OH_AVErrCode code = OH_AudioCodec_QueryInputBuffer(media.codec, &index, kQueryTimeoutUs);
            if (code == AV_ERR_OK) {
                OH_AVBuffer *buffer = OH_AudioCodec_GetInputBuffer(media.codec, index);
                Require(buffer != nullptr, "subtitle_codec");
                OH_AVCodecBufferAttr attr {};
                bool eos = OH_AVDemuxer_ReadSampleBuffer(media.demuxer, media.track, buffer) != AV_ERR_OK;
                if (!eos) {
                    OH_AVBuffer_GetBufferAttr(buffer, &attr);
                    // 读到文件尾，或已经超过需要的范围（留 0.5 秒给解码器延迟）就送结束标记。
                    eos = (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0 || attr.pts / 1000 > endMs + 500;
                }
                if (eos) {
                    attr.size = 0;
                    attr.offset = 0;
                    attr.flags = AVCODEC_BUFFER_FLAGS_EOS;
                    OH_AVBuffer_SetBufferAttr(buffer, &attr);
                    inputDone = true;
                }
                Require(OH_AudioCodec_PushInputBuffer(media.codec, index) == AV_ERR_OK, "subtitle_codec");
            } else {
                Require(code == AV_ERR_TRY_AGAIN_LATER, "subtitle_codec");
            }
        }

        uint32_t index = 0;
        OH_AVErrCode code = OH_AudioCodec_QueryOutputBuffer(media.codec, &index, kQueryTimeoutUs);
        if (code == AV_ERR_STREAM_CHANGED) {
            ReadOutputFormat(media.codec, pcm);
            continue;
        }
        if (code == AV_ERR_TRY_AGAIN_LATER) continue;
        Require(code == AV_ERR_OK, "subtitle_codec");
        OH_AVBuffer *buffer = OH_AudioCodec_GetOutputBuffer(media.codec, index);
        Require(buffer != nullptr, "subtitle_codec");
        OH_AVCodecBufferAttr attr {};
        OH_AVBuffer_GetBufferAttr(buffer, &attr);
        if (pcm.rate <= 0 || pcm.channels <= 0) ReadOutputFormat(media.codec, pcm);
        const int32_t bytes = BytesPerSample(pcm.sampleFormat);
        const uint8_t *data = OH_AVBuffer_GetAddr(buffer);
        if (data && attr.size > 0 && bytes > 0 && pcm.rate > 0 && pcm.channels > 0) {
            data += attr.offset;
            const int32_t frameBytes = bytes * pcm.channels;
            const int32_t frames = attr.size / frameBytes;
            const double frameMs = 1000.0 / pcm.rate;
            const double firstMs = attr.pts / 1000.0;
            for (int32_t i = 0; i < frames; i++) {
                const double t = firstMs + i * frameMs;
                if (t < startMs) continue;
                if (t >= endMs) {
                    outputDone = true;
                    break;
                }
                float sum = 0.0f;
                const uint8_t *frame = data + static_cast<size_t>(i) * frameBytes;
                for (int32_t c = 0; c < pcm.channels; c++) sum += SampleAt(frame + c * bytes, pcm.sampleFormat);
                mono.push_back(sum / pcm.channels);
            }
        }
        if ((attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0) outputDone = true;
        OH_AudioCodec_FreeOutputBuffer(media.codec, index);
    }
    Require(pcm.rate > 0 || mono.empty(), "subtitle_codec");
    result.samples = Resample(mono, pcm.rate > 0 ? pcm.rate : targetRate, targetRate);
    return result;
}

std::string StringArg(napi_env env, napi_value value)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) return "";
    std::string text(length, '\0');
    napi_get_value_string_utf8(env, value, text.data(), length + 1, &length);
    return text;
}

int64_t NumberArg(napi_env env, napi_value value)
{
    double number = 0;
    napi_get_value_double(env, value, &number);
    return std::isfinite(number) ? static_cast<int64_t>(number) : 0;
}

void SetNumber(napi_env env, napi_value object, const char *name, double value)
{
    napi_value number;
    napi_create_double(env, value, &number);
    napi_set_named_property(env, object, name, number);
}

/**
 * decode(path, startMs, spanMs, sampleRate?) → { samples: Float32Array, sampleRate, startMs, durationMs }。
 * sampleRate 缺省 16000（字幕识别用）；朗读把压缩音频解成 PCM 时传播放用的采样率。
 */
napi_value DecodeApi(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value args[4] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 3) {
        napi_throw_error(env, nullptr, "subtitle_args");
        return nullptr;
    }
    const std::string path = StringArg(env, args[0]);
    const int64_t startMs = NumberArg(env, args[1]) > 0 ? NumberArg(env, args[1]) : 0;
    int64_t spanMs = NumberArg(env, args[2]);
    if (path.empty() || path[0] != '/' || spanMs <= 0) {
        napi_throw_error(env, nullptr, "subtitle_args");
        return nullptr;
    }
    if (spanMs > kMaxSpanMs) spanMs = kMaxSpanMs;
    int32_t targetRate = kTargetRate;
    if (argc >= 4) {
        const int64_t wanted = NumberArg(env, args[3]);
        if (wanted >= 8000 && wanted <= 48000) targetRate = static_cast<int32_t>(wanted);
    }
    try {
        DecodeResult result = Decode(path, startMs, spanMs, targetRate);
        void *data = nullptr;
        napi_value buffer;
        napi_value array;
        const size_t bytes = result.samples.size() * sizeof(float);
        napi_create_arraybuffer(env, bytes, &data, &buffer);
        if (bytes > 0 && data) std::memcpy(data, result.samples.data(), bytes);
        napi_create_typedarray(env, napi_float32_array, result.samples.size(), buffer, 0, &array);
        napi_value object;
        napi_create_object(env, &object);
        napi_set_named_property(env, object, "samples", array);
        SetNumber(env, object, "sampleRate", targetRate);
        SetNumber(env, object, "startMs", static_cast<double>(result.startMs));
        SetNumber(env, object, "durationMs", static_cast<double>(result.durationMs));
        return object;
    } catch (const std::exception &error) {
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    }
}

/** probe(path) → 总时长（毫秒），未知时为 0。 */
napi_value ProbeApi(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    const std::string path = argc > 0 ? StringArg(env, args[0]) : "";
    if (path.empty() || path[0] != '/') {
        napi_throw_error(env, nullptr, "subtitle_args");
        return nullptr;
    }
    try {
        Media media;
        Open(media, path);
        napi_value value;
        napi_create_double(env, static_cast<double>(media.durationMs), &value);
        return value;
    } catch (const std::exception &error) {
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    }
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor descriptors[] = {
        {"decode", nullptr, DecodeApi, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"probe", nullptr, ProbeApi, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
    return exports;
}

napi_module g_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "subtitle_audio",
    .nm_priv = nullptr,
    .reserved = {0},
};

}  // namespace

extern "C" __attribute__((constructor)) void RegisterSubtitleAudioModule(void)
{
    napi_module_register(&g_module);
}
