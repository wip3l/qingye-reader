// 仿真翻页的 GPU 渲染：把当前页纹理按折线切成几块，把折线另一侧的纸卷成圆柱，
// 卷过半圈的部分平压回本页上方，纸背透出反向的正文并罩一层纸色。卷页下面的目标页由 ArkUI
// 照常绘制，这里只画卷起的纸和它投在目标页上的阴影，其余像素透明。
//
// 画在 TEXTURE 类型的 XComponent 上，与 ArkUI 同帧合成。所有调用都在 UI 线程同步进行：
// 每帧一次绘制约一毫秒，纹理只在翻页开始时上传一次。
#include <napi/native_api.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <hilog/log.h>
#include <multimedia/image_framework/image/pixelmap_native.h>
#include <native_window/external_window.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <map>
#include <string>
#include <vector>

namespace {

constexpr unsigned int kLogDomain = 0xD0A1;
constexpr const char *kLogTag = "PageCurl";
// 纸面每帧顺着折线切：折线这边的平铺部分、半圈弧面上的 kCurlSlices 条细条、平压回来的部分，
// 各自是纸的矩形被两条平行线截出的凸多边形。弧顶和各段交界都落在切线上，边缘是直线；
// 早先用固定的整页网格时，斜着的弧顶穿过网格格子，高密度屏上会出现一格一格的台阶。
constexpr int kCurlSlices = 48;

#ifndef EGL_OPENGL_ES3_BIT
#define EGL_OPENGL_ES3_BIT 0x00000040
#endif

void LogWarn(const std::string &message)
{
    OH_LOG_Print(LOG_APP, LOG_WARN, kLogDomain, kLogTag, "%{public}s", message.c_str());
}

const char *kLeafVertex = R"(#version 300 es
layout(location = 0) in vec2 aUv;
uniform vec2 uSize;
uniform vec2 uP0;
uniform vec2 uN;
uniform float uR;
uniform float uActive;
uniform float uZ;
out vec2 vUv;
out float vTheta;
out float vD;
const float PI = 3.14159265;
void main() {
  vec2 p = aUv * uSize;
  float d = dot(p - uP0, uN);
  vec2 q = p;
  float z = 0.0;
  float th = 0.0;
  if (uActive > 0.5 && d > 0.0) {
    if (d < PI * uR) {
      th = d / uR;
      q = p - uN * d + uN * (uR * sin(th));
      z = uR * (1.0 - cos(th));
    } else {
      th = PI;
      q = p - uN * d - uN * (d - PI * uR);
      z = 2.0 * uR;
    }
  }
  vUv = aUv;
  vTheta = th;
  vD = d;
  gl_Position = vec4(q.x / uSize.x * 2.0 - 1.0, 1.0 - q.y / uSize.y * 2.0, 0.5 - z * uZ, 1.0);
}
)";

const char *kLeafFragment = R"(#version 300 es
precision highp float;
in vec2 vUv;
in float vTheta;
in float vD;
uniform sampler2D uTex;
uniform vec2 uSize;
uniform vec2 uP0;
uniform vec2 uN;
uniform float uR;
uniform float uActive;
uniform float uShadow;
uniform float uShade;
uniform float uBackWash;
uniform float uSwapRB;
uniform float uPremul;
uniform vec3 uPaper;
uniform float uDark;
uniform vec3 uPaperBack;
uniform float uHasPaperBack;
out vec4 fragColor;
const float PI = 3.14159265;
float outsideDistance(vec2 p) {
  vec2 a = -p;
  vec2 b = p - uSize;
  return max(max(a.x, b.x), max(a.y, b.y));
}
void main() {
  vec4 t = texture(uTex, vUv);
  if (uSwapRB > 0.5) t.rgb = t.bgr;
  vec3 c = uPremul > 0.5 ? t.rgb + uPaper * (1.0 - t.a) : mix(uPaper, t.rgb, t.a);
  float th = vTheta;
  bool back = th > PI * 0.5;
  if (back) {
    // 纸背：同一张纸的另一面，底色是上传纹理时从整页取样得到的纸色（中位数，不含正文墨色），
    // 背景图主题也对得上；正文只隐约透出反向的字。不能用局部模糊：模糊会把每行字晕成一条灰云。
    // 夜间纸背略提亮一点，从深色页面上分得出来。
    vec3 paperBack = uHasPaperBack > 0.5 ? uPaperBack : uPaper;
    if (uDark > 0.5) paperBack = min(vec3(1.0), paperBack + 0.03);
    c = mix(c, paperBack, uBackWash);
  }
  if (uActive > 0.5) {
    if (th > 0.0) {
      // 纸背整体只比本页暗一点；弧面上离弧顶约三分之一半圈处（θ≈150°）有一道很淡的亮带，像纸面反光，
      // 卷起的正面不做明暗。最深的影子不画在纸上，只投在弧顶外侧的下一页上（阴影着色器）。
      // 早先在弧顶附近把纸压暗，和外侧投影连成一大片，像一圈黑色光晕；真实的纸弧顶背面迎着光，反而偏亮。
      if (back) {
        c *= 1.0 - uShade * 0.1;
        float u = (th - PI * 0.5) / (PI * 0.5);
        float band = smoothstep(0.0, 1.0, clamp(1.0 - abs(u - 0.6667) / 0.3333, 0.0, 1.0));
        c = mix(c, vec3(1.0), band * (uDark > 0.5 ? 0.06 : 0.16));
      }
    } else {
      // 平压回来的那片纸在本页上的软影：把这一点按折线镜像回纸上的原位置，原位置离纸边越近影子越深。
      vec2 origin = vUv * uSize + uN * (PI * uR - 2.0 * vD);
      float e = outsideDistance(origin);
      float width = 5.0 + uR * 0.4;
      float s = e > 0.0 ? 1.0 - smoothstep(0.0, width, e) : 0.0;
      c *= 1.0 - s * 0.24 * uShadow;
    }
  }
  fragColor = vec4(c, 1.0);
}
)";

const char *kShadowVertex = R"(#version 300 es
layout(location = 0) in vec2 aUv;
uniform vec2 uSize;
out vec2 vPage;
void main() {
  vPage = aUv * uSize;
  gl_Position = vec4(aUv.x * 2.0 - 1.0, 1.0 - aUv.y * 2.0, 0.99, 1.0);
}
)";

// 卷起的纸投在目标页上的阴影：只画在弧顶外侧，沿折线方向只在纸确实存在的那一段。
const char *kShadowFragment = R"(#version 300 es
precision highp float;
in vec2 vPage;
uniform vec2 uSize;
uniform vec2 uP0;
uniform vec2 uN;
uniform float uR;
uniform float uShadow;
out vec4 fragColor;
const float PI = 3.14159265;
float outsideDistance(vec2 p) {
  vec2 a = -p;
  vec2 b = p - uSize;
  return max(max(a.x, b.x), max(a.y, b.y));
}
void main() {
  float s = dot(vPage - uP0, uN);
  vec2 crest = vPage + uN * (PI * uR * 0.5 - s);
  float mask = 1.0 - smoothstep(0.0, 16.0, outsideDistance(crest));
  float x = s - uR;
  // 浅色纸（尤其牛皮纸）上纯黑叠太深会发浑，最深约 27%，散得宽一些。
  float width = 10.0 + uR * 1.4;
  float shade = x > 0.0 ? pow(1.0 - smoothstep(0.0, width, x), 1.6) : 1.0;
  fragColor = vec4(0.0, 0.0, 0.0, shade * mask * 0.45 * uShadow);
}
)";

struct LeafUniforms {
    GLint size = -1, p0 = -1, n = -1, r = -1, active = -1, z = -1;
    GLint tex = -1, shadow = -1, shade = -1, backWash = -1, swapRB = -1, premul = -1, paper = -1, dark = -1, paperBack = -1, hasPaperBack = -1;
};

struct ShadowUniforms {
    GLint size = -1, p0 = -1, n = -1, r = -1, shadow = -1;
};

struct Gpu {
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLConfig config = nullptr;
    EGLContext context = EGL_NO_CONTEXT;
    bool failed = false;
    bool programsReady = false;
    GLuint leafProgram = 0;
    GLuint shadowProgram = 0;
    LeafUniforms leaf;
    ShadowUniforms shadow;
    GLuint meshVao = 0;
    GLuint meshVbo = 0;
    std::vector<GLfloat> meshVertices;
    GLuint quadVao = 0;
    GLuint quadVbo = 0;
    GLint maxTextureSize = 4096;
};

struct Surface {
    OHNativeWindow *window = nullptr;
    EGLSurface surface = EGL_NO_SURFACE;
    int32_t width = 0;
    int32_t height = 0;
    GLuint texture = 0;
    uint32_t textureWidth = 0;
    uint32_t textureHeight = 0;
    bool hasTexture = false;
    bool swapRB = false;
    bool premultiplied = true;
    bool hasPaperBack = false;
    float paperBack[3] = {1, 1, 1};
};

Gpu g_gpu;
std::map<std::string, Surface> g_surfaces;

bool InitDisplay()
{
    if (g_gpu.failed) return false;
    if (g_gpu.context != EGL_NO_CONTEXT) return true;
    g_gpu.display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (g_gpu.display == EGL_NO_DISPLAY || !eglInitialize(g_gpu.display, nullptr, nullptr)) {
        LogWarn("eglInitialize failed");
        g_gpu.failed = true;
        return false;
    }
    // 先要 4 倍多重采样，卷起的纸边才不会出锯齿；拿不到就退回不采样的配置。
    const EGLint withMsaa[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_DEPTH_SIZE, 16,
        EGL_SAMPLE_BUFFERS, 1, EGL_SAMPLES, 4, EGL_NONE
    };
    const EGLint plain[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_DEPTH_SIZE, 16, EGL_NONE
    };
    EGLint count = 0;
    if (!eglChooseConfig(g_gpu.display, withMsaa, &g_gpu.config, 1, &count) || count < 1) {
        count = 0;
        if (!eglChooseConfig(g_gpu.display, plain, &g_gpu.config, 1, &count) || count < 1) {
            LogWarn("eglChooseConfig failed");
            g_gpu.failed = true;
            return false;
        }
    }
    const EGLint contextAttribs[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
    g_gpu.context = eglCreateContext(g_gpu.display, g_gpu.config, EGL_NO_CONTEXT, contextAttribs);
    if (g_gpu.context == EGL_NO_CONTEXT) {
        LogWarn("eglCreateContext failed: " + std::to_string(eglGetError()));
        g_gpu.failed = true;
        return false;
    }
    return true;
}

GLuint Compile(GLenum type, const char *source)
{
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);
    GLint ok = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[512] = {0};
        glGetShaderInfoLog(shader, sizeof(log) - 1, nullptr, log);
        LogWarn(std::string("shader compile failed: ") + log);
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

GLuint Link(const char *vertex, const char *fragment)
{
    GLuint vs = Compile(GL_VERTEX_SHADER, vertex);
    GLuint fs = Compile(GL_FRAGMENT_SHADER, fragment);
    if (!vs || !fs) {
        if (vs) glDeleteShader(vs);
        if (fs) glDeleteShader(fs);
        return 0;
    }
    GLuint program = glCreateProgram();
    glAttachShader(program, vs);
    glAttachShader(program, fs);
    glLinkProgram(program);
    glDeleteShader(vs);
    glDeleteShader(fs);
    GLint ok = 0;
    glGetProgramiv(program, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[512] = {0};
        glGetProgramInfoLog(program, sizeof(log) - 1, nullptr, log);
        LogWarn(std::string("program link failed: ") + log);
        glDeleteProgram(program);
        return 0;
    }
    return program;
}

// 需要一个已绑定的窗口表面才能编译着色器，所以在第一次 attach 之后才做。
bool InitPrograms()
{
    if (g_gpu.programsReady) return true;
    g_gpu.leafProgram = Link(kLeafVertex, kLeafFragment);
    g_gpu.shadowProgram = Link(kShadowVertex, kShadowFragment);
    if (!g_gpu.leafProgram || !g_gpu.shadowProgram) {
        g_gpu.failed = true;
        return false;
    }
    GLuint p = g_gpu.leafProgram;
    g_gpu.leaf.size = glGetUniformLocation(p, "uSize");
    g_gpu.leaf.p0 = glGetUniformLocation(p, "uP0");
    g_gpu.leaf.n = glGetUniformLocation(p, "uN");
    g_gpu.leaf.r = glGetUniformLocation(p, "uR");
    g_gpu.leaf.active = glGetUniformLocation(p, "uActive");
    g_gpu.leaf.z = glGetUniformLocation(p, "uZ");
    g_gpu.leaf.tex = glGetUniformLocation(p, "uTex");
    g_gpu.leaf.shadow = glGetUniformLocation(p, "uShadow");
    g_gpu.leaf.shade = glGetUniformLocation(p, "uShade");
    g_gpu.leaf.backWash = glGetUniformLocation(p, "uBackWash");
    g_gpu.leaf.swapRB = glGetUniformLocation(p, "uSwapRB");
    g_gpu.leaf.premul = glGetUniformLocation(p, "uPremul");
    g_gpu.leaf.paper = glGetUniformLocation(p, "uPaper");
    g_gpu.leaf.dark = glGetUniformLocation(p, "uDark");
    g_gpu.leaf.paperBack = glGetUniformLocation(p, "uPaperBack");
    g_gpu.leaf.hasPaperBack = glGetUniformLocation(p, "uHasPaperBack");
    p = g_gpu.shadowProgram;
    g_gpu.shadow.size = glGetUniformLocation(p, "uSize");
    g_gpu.shadow.p0 = glGetUniformLocation(p, "uP0");
    g_gpu.shadow.n = glGetUniformLocation(p, "uN");
    g_gpu.shadow.r = glGetUniformLocation(p, "uR");
    g_gpu.shadow.shadow = glGetUniformLocation(p, "uShadow");

    // 纸面顶点每帧按折线重算，缓冲区只建一次。
    glGenVertexArrays(1, &g_gpu.meshVao);
    glBindVertexArray(g_gpu.meshVao);
    glGenBuffers(1, &g_gpu.meshVbo);
    glBindBuffer(GL_ARRAY_BUFFER, g_gpu.meshVbo);
    glBufferData(GL_ARRAY_BUFFER, 4096 * sizeof(GLfloat), nullptr, GL_STREAM_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, nullptr);
    glBindVertexArray(0);

    const GLfloat quad[] = {0, 0, 1, 0, 0, 1, 1, 1};
    glGenVertexArrays(1, &g_gpu.quadVao);
    glBindVertexArray(g_gpu.quadVao);
    glGenBuffers(1, &g_gpu.quadVbo);
    glBindBuffer(GL_ARRAY_BUFFER, g_gpu.quadVbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(quad), quad, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, nullptr);
    glBindVertexArray(0);
    glGetIntegerv(GL_MAX_TEXTURE_SIZE, &g_gpu.maxTextureSize);
    g_gpu.programsReady = true;
    return true;
}

bool MakeCurrent(Surface &surface)
{
    if (surface.surface == EGL_NO_SURFACE) return false;
    if (!eglMakeCurrent(g_gpu.display, surface.surface, surface.surface, g_gpu.context)) {
        LogWarn("eglMakeCurrent failed: " + std::to_string(eglGetError()));
        return false;
    }
    return true;
}

void DestroySurface(Surface &surface)
{
    if (surface.surface != EGL_NO_SURFACE) {
        if (MakeCurrent(surface) && surface.texture) glDeleteTextures(1, &surface.texture);
        eglMakeCurrent(g_gpu.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        eglDestroySurface(g_gpu.display, surface.surface);
    }
    if (surface.window) OH_NativeWindow_DestroyNativeWindow(surface.window);
    surface = Surface();
}

std::string ArgString(napi_env env, napi_value value)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) return "";
    std::string text(length, '\0');
    napi_get_value_string_utf8(env, value, text.data(), length + 1, &length);
    return text;
}

double ArgNumber(napi_env env, napi_value value, double fallback = 0)
{
    double result = fallback;
    if (napi_get_value_double(env, value, &result) != napi_ok) return fallback;
    return result;
}

napi_value Bool(napi_env env, bool value)
{
    napi_value result;
    napi_get_boolean(env, value, &result);
    return result;
}

void ApplyGeometry(Surface &surface, int32_t width, int32_t height)
{
    surface.width = width;
    surface.height = height;
    if (surface.window) OH_NativeWindow_NativeWindowHandleOpt(surface.window, SET_BUFFER_GEOMETRY, width, height);
}

// attach(surfaceId, widthPx, heightPx): boolean
napi_value Attach(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 3) return Bool(env, false);
    std::string id = ArgString(env, args[0]);
    int32_t width = static_cast<int32_t>(ArgNumber(env, args[1]));
    int32_t height = static_cast<int32_t>(ArgNumber(env, args[2]));
    if (id.empty() || width <= 0 || height <= 0 || !InitDisplay()) return Bool(env, false);
    auto found = g_surfaces.find(id);
    if (found != g_surfaces.end() && found->second.surface != EGL_NO_SURFACE) {
        ApplyGeometry(found->second, width, height);
        return Bool(env, true);
    }
    Surface surface;
    uint64_t surfaceId = std::strtoull(id.c_str(), nullptr, 10);
    if (OH_NativeWindow_CreateNativeWindowFromSurfaceId(surfaceId, &surface.window) != 0 || !surface.window) {
        LogWarn("create native window failed");
        return Bool(env, false);
    }
    ApplyGeometry(surface, width, height);
    surface.surface = eglCreateWindowSurface(g_gpu.display, g_gpu.config,
        reinterpret_cast<EGLNativeWindowType>(surface.window), nullptr);
    if (surface.surface == EGL_NO_SURFACE) {
        LogWarn("eglCreateWindowSurface failed: " + std::to_string(eglGetError()));
        OH_NativeWindow_DestroyNativeWindow(surface.window);
        return Bool(env, false);
    }
    if (!MakeCurrent(surface) || !InitPrograms()) {
        DestroySurface(surface);
        return Bool(env, false);
    }
    // 绘制节奏跟随 ArkUI 的动画帧，交换缓冲区不等垂直同步，免得卡住 UI 线程。
    eglSwapInterval(g_gpu.display, 0);
    glClearColor(0, 0, 0, 0);
    glClear(GL_COLOR_BUFFER_BIT);
    eglSwapBuffers(g_gpu.display, surface.surface);
    g_surfaces[id] = surface;
    return Bool(env, true);
}

// detach(surfaceId): void
napi_value Detach(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) return nullptr;
    auto found = g_surfaces.find(ArgString(env, args[0]));
    if (found == g_surfaces.end()) return nullptr;
    DestroySurface(found->second);
    g_surfaces.erase(found);
    return nullptr;
}

// 这一页的纸色：整页均匀取约 4600 个不透明像素，红绿蓝各取中位数。正文只占页面一小部分，
// 中位数落在纸上而不是字上；背景图主题取到的是背景图的主色调。
void SamplePaperColor(const uint8_t *pixels, uint32_t width, uint32_t height, uint32_t rowStride, bool bgra,
    bool premultiplied, Surface &surface)
{
    constexpr int kColumns = 48;
    constexpr int kRows = 96;
    std::vector<uint8_t> channels[3];
    for (auto &channel : channels) channel.reserve(kColumns * kRows);
    for (int row = 0; row < kRows; row++) {
        const uint32_t y = static_cast<uint32_t>((row + 0.5) * height / kRows);
        for (int column = 0; column < kColumns; column++) {
            const uint32_t x = static_cast<uint32_t>((column + 0.5) * width / kColumns);
            const uint8_t *pixel = pixels + static_cast<size_t>(y) * rowStride + static_cast<size_t>(x) * 4;
            const uint8_t alpha = pixel[3];
            if (alpha < 250) continue;
            channels[0].push_back(bgra ? pixel[2] : pixel[0]);
            channels[1].push_back(pixel[1]);
            channels[2].push_back(bgra ? pixel[0] : pixel[2]);
        }
    }
    (void)premultiplied;  // 只取几乎不透明的像素，预乘与否结果相同。
    surface.hasPaperBack = channels[0].size() >= 64;
    if (!surface.hasPaperBack) return;
    for (int index = 0; index < 3; index++) {
        auto &channel = channels[index];
        auto middle = channel.begin() + static_cast<std::ptrdiff_t>(channel.size() / 2);
        std::nth_element(channel.begin(), middle, channel.end());
        surface.paperBack[index] = static_cast<float>(*middle) / 255.0f;
    }
}

// upload(surfaceId, pixelMap): boolean。只接受 RGBA_8888 / BGRA_8888，其余格式返回 false 由页面退回 Canvas。
napi_value Upload(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) return Bool(env, false);
    auto found = g_surfaces.find(ArgString(env, args[0]));
    if (found == g_surfaces.end() || !MakeCurrent(found->second)) return Bool(env, false);
    Surface &surface = found->second;
    OH_PixelmapNative *pixelmap = nullptr;
    if (OH_PixelmapNative_ConvertPixelmapNativeFromNapi(env, args[1], &pixelmap) != IMAGE_SUCCESS || !pixelmap) {
        LogWarn("convert pixelmap failed");
        return Bool(env, false);
    }
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t rowStride = 0;
    int32_t format = 0;
    int32_t alphaType = 0;
    OH_Pixelmap_ImageInfo *imageInfo = nullptr;
    OH_PixelmapImageInfo_Create(&imageInfo);
    bool infoOk = imageInfo && OH_PixelmapNative_GetImageInfo(pixelmap, imageInfo) == IMAGE_SUCCESS;
    if (infoOk) {
        OH_PixelmapImageInfo_GetWidth(imageInfo, &width);
        OH_PixelmapImageInfo_GetHeight(imageInfo, &height);
        OH_PixelmapImageInfo_GetRowStride(imageInfo, &rowStride);
        OH_PixelmapImageInfo_GetPixelFormat(imageInfo, &format);
        OH_PixelmapImageInfo_GetAlphaType(imageInfo, &alphaType);
    }
    if (imageInfo) OH_PixelmapImageInfo_Release(imageInfo);
    bool supported = infoOk && width > 0 && height > 0 &&
        (format == PIXEL_FORMAT_RGBA_8888 || format == PIXEL_FORMAT_BGRA_8888) &&
        rowStride >= width * 4 && rowStride % 4 == 0 &&
        static_cast<GLint>(width) <= g_gpu.maxTextureSize && static_cast<GLint>(height) <= g_gpu.maxTextureSize;
    void *pixels = nullptr;
    if (!supported || OH_PixelmapNative_AccessPixels(pixelmap, &pixels) != IMAGE_SUCCESS || !pixels) {
        LogWarn("unsupported pixelmap: format=" + std::to_string(format) + " size=" + std::to_string(width) + "x" +
            std::to_string(height));
        OH_PixelmapNative_Destroy(&pixelmap);
        return Bool(env, false);
    }
    if (!surface.texture) glGenTextures(1, &surface.texture);
    glBindTexture(GL_TEXTURE_2D, surface.texture);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, static_cast<GLint>(rowStride / 4));
    if (width != surface.textureWidth || height != surface.textureHeight) {
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, static_cast<GLsizei>(width), static_cast<GLsizei>(height), 0,
            GL_RGBA, GL_UNSIGNED_BYTE, pixels);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        surface.textureWidth = width;
        surface.textureHeight = height;
    } else {
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, static_cast<GLsizei>(width), static_cast<GLsizei>(height), GL_RGBA,
            GL_UNSIGNED_BYTE, pixels);
    }
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
    // 弧面靠近折痕处纹理被压得很窄，多级纹理让那里的字不闪。
    glGenerateMipmap(GL_TEXTURE_2D);
    SamplePaperColor(static_cast<const uint8_t *>(pixels), width, height, rowStride,
        format == PIXEL_FORMAT_BGRA_8888, alphaType != PIXELMAP_ALPHA_TYPE_UNPREMULTIPLIED, surface);
    OH_PixelmapNative_UnaccessPixels(pixelmap);
    OH_PixelmapNative_Destroy(&pixelmap);
    surface.hasTexture = glGetError() == GL_NO_ERROR;
    surface.swapRB = format == PIXEL_FORMAT_BGRA_8888;
    surface.premultiplied = alphaType != PIXELMAP_ALPHA_TYPE_UNPREMULTIPLIED;
    return Bool(env, surface.hasTexture);
}

struct Point {
    double x;
    double y;
};

// 保留凸多边形里 sign * (dot(p - p0, n) - limit) >= 0 的部分（Sutherland–Hodgman）。用双精度，
// 相邻两块在同一条切线上算出的交点转成 float 后完全一致，块与块之间不留缝。
std::vector<Point> ClipHalfPlane(const std::vector<Point> &polygon, const Point &p0, const Point &n, double limit,
    double sign)
{
    std::vector<Point> result;
    const size_t count = polygon.size();
    for (size_t index = 0; index < count; index++) {
        const Point &current = polygon[index];
        const Point &next = polygon[(index + 1) % count];
        const double a = sign * ((current.x - p0.x) * n.x + (current.y - p0.y) * n.y - limit);
        const double b = sign * ((next.x - p0.x) * n.x + (next.y - p0.y) * n.y - limit);
        if (a >= 0) result.push_back(current);
        if ((a >= 0) != (b >= 0)) {
            const double t = a / (a - b);
            result.push_back({current.x + (next.x - current.x) * t, current.y + (next.y - current.y) * t});
        }
    }
    return result;
}

// 纸面顶点（以页宽高归一化）：折线这边整块平铺、弧面切成细条、卷过半圈的部分整块平压回来。
void BuildLeafMesh(double width, double height, bool active, const Point &p0, const Point &n, double radius,
    std::vector<GLfloat> &out)
{
    out.clear();
    const std::vector<Point> page = {{0, 0}, {width, 0}, {width, height}, {0, height}};
    auto addPolygon = [&](const std::vector<Point> &polygon) {
        if (polygon.size() < 3) return;
        for (size_t index = 1; index + 1 < polygon.size(); index++) {
            for (const Point *point : {&polygon[0], &polygon[index], &polygon[index + 1]}) {
                out.push_back(static_cast<GLfloat>(point->x / width));
                out.push_back(static_cast<GLfloat>(point->y / height));
            }
        }
    };
    if (!active) {
        addPolygon(page);
        return;
    }
    const double halfTurn = M_PI * radius;
    addPolygon(ClipHalfPlane(page, p0, n, 0, -1));
    for (int slice = 0; slice < kCurlSlices; slice++) {
        const double from = halfTurn * slice / kCurlSlices;
        const double to = halfTurn * (slice + 1) / kCurlSlices;
        addPolygon(ClipHalfPlane(ClipHalfPlane(page, p0, n, from, 1), p0, n, to, -1));
    }
    addPolygon(ClipHalfPlane(page, p0, n, halfTurn, 1));
}

enum RenderParam {
    kWidth = 0, kHeight, kPxPerVp, kActive, kP0x, kP0y, kNx, kNy, kRadius, kShadow, kShade,
    kPaperR, kPaperG, kPaperB, kDark, kBackWash, kParamCount
};

// render(surfaceId, params: number[]): boolean。参数顺序见 RenderParam，长度单位都是 vp。
napi_value Render(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) return Bool(env, false);
    auto found = g_surfaces.find(ArgString(env, args[0]));
    if (found == g_surfaces.end() || !MakeCurrent(found->second)) return Bool(env, false);
    Surface &surface = found->second;
    double p[kParamCount] = {0};
    uint32_t length = 0;
    napi_get_array_length(env, args[1], &length);
    for (uint32_t index = 0; index < length && index < kParamCount; index++) {
        napi_value item;
        napi_get_element(env, args[1], index, &item);
        p[index] = ArgNumber(env, item);
    }
    const float width = static_cast<float>(std::max(1.0, p[kWidth]));
    const float height = static_cast<float>(std::max(1.0, p[kHeight]));
    const double pxPerVp = p[kPxPerVp] > 0 ? p[kPxPerVp] : static_cast<double>(surface.width) / width;
    // 卷页内容按 vp 尺寸铺在表面顶部；截图高度偶尔比组件矮几个像素，底下留透明而不是拉伸正文。
    const GLsizei viewWidth = std::min(surface.width, static_cast<int32_t>(std::lround(width * pxPerVp)));
    const GLsizei viewHeight = std::min(surface.height, static_cast<int32_t>(std::lround(height * pxPerVp)));
    glViewport(0, surface.height - viewHeight, viewWidth, viewHeight);
    glDisable(GL_SCISSOR_TEST);
    glClearColor(0, 0, 0, 0);
    glClearDepthf(1.0f);
    glDepthMask(GL_TRUE);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    if (surface.hasTexture) {
        const bool active = p[kActive] > 0.5;
        const float radius = static_cast<float>(std::max(0.5, p[kRadius]));
        glEnable(GL_DEPTH_TEST);
        glDepthFunc(GL_LESS);
        glDisable(GL_BLEND);
        glDisable(GL_CULL_FACE);
        if (active) {
            glUseProgram(g_gpu.shadowProgram);
            glUniform2f(g_gpu.shadow.size, width, height);
            glUniform2f(g_gpu.shadow.p0, static_cast<float>(p[kP0x]), static_cast<float>(p[kP0y]));
            glUniform2f(g_gpu.shadow.n, static_cast<float>(p[kNx]), static_cast<float>(p[kNy]));
            glUniform1f(g_gpu.shadow.r, radius);
            glUniform1f(g_gpu.shadow.shadow, static_cast<float>(p[kShadow]));
            glBindVertexArray(g_gpu.quadVao);
            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        }
        glUseProgram(g_gpu.leafProgram);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, surface.texture);
        glUniform1i(g_gpu.leaf.tex, 0);
        glUniform2f(g_gpu.leaf.size, width, height);
        glUniform2f(g_gpu.leaf.p0, static_cast<float>(p[kP0x]), static_cast<float>(p[kP0y]));
        glUniform2f(g_gpu.leaf.n, static_cast<float>(p[kNx]), static_cast<float>(p[kNy]));
        glUniform1f(g_gpu.leaf.r, radius);
        glUniform1f(g_gpu.leaf.active, active ? 1.0f : 0.0f);
        glUniform1f(g_gpu.leaf.z, 0.45f / (2.0f * radius + 1.0f));
        glUniform1f(g_gpu.leaf.shadow, static_cast<float>(p[kShadow]));
        glUniform1f(g_gpu.leaf.shade, static_cast<float>(p[kShade]));
        glUniform1f(g_gpu.leaf.backWash, static_cast<float>(p[kBackWash]));
        glUniform1f(g_gpu.leaf.swapRB, surface.swapRB ? 1.0f : 0.0f);
        glUniform1f(g_gpu.leaf.premul, surface.premultiplied ? 1.0f : 0.0f);
        glUniform3f(g_gpu.leaf.paper, static_cast<float>(p[kPaperR]), static_cast<float>(p[kPaperG]),
            static_cast<float>(p[kPaperB]));
        glUniform1f(g_gpu.leaf.dark, p[kDark] > 0.5 ? 1.0f : 0.0f);
        glUniform3f(g_gpu.leaf.paperBack, surface.paperBack[0], surface.paperBack[1], surface.paperBack[2]);
        glUniform1f(g_gpu.leaf.hasPaperBack, surface.hasPaperBack ? 1.0f : 0.0f);
        BuildLeafMesh(width, height, active, {p[kP0x], p[kP0y]}, {p[kNx], p[kNy]}, radius, g_gpu.meshVertices);
        glBindVertexArray(g_gpu.meshVao);
        glBindBuffer(GL_ARRAY_BUFFER, g_gpu.meshVbo);
        glBufferData(GL_ARRAY_BUFFER, static_cast<GLsizeiptr>(g_gpu.meshVertices.size() * sizeof(GLfloat)),
            g_gpu.meshVertices.data(), GL_STREAM_DRAW);
        glDrawArrays(GL_TRIANGLES, 0, static_cast<GLsizei>(g_gpu.meshVertices.size() / 2));
        glBindVertexArray(0);
    }
    if (!eglSwapBuffers(g_gpu.display, surface.surface)) {
        LogWarn("eglSwapBuffers failed: " + std::to_string(eglGetError()));
        return Bool(env, false);
    }
    return Bool(env, true);
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor descriptors[] = {
        {"attach", nullptr, Attach, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"detach", nullptr, Detach, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"upload", nullptr, Upload, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"render", nullptr, Render, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
    return exports;
}

napi_module g_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "page_curl",
    .nm_priv = nullptr,
    .reserved = {0},
};

}  // namespace

extern "C" __attribute__((constructor)) void RegisterPageCurlModule(void)
{
    napi_module_register(&g_module);
}
