import { image } from '@kit.ImageKit';

/** 绑定 XComponent 的表面（宽高为像素）；同一表面再次调用只更新尺寸。 */
export const attach: (surfaceId: string, widthPx: number, heightPx: number) => boolean;
export const detach: (surfaceId: string) => void;
/** 把卷起的那页上传成纹理；只支持 RGBA_8888 / BGRA_8888。 */
export const upload: (surfaceId: string, pixelMap: image.PixelMap) => boolean;
/**
 * 画一帧。params 依次为：宽、高（vp）、每 vp 像素数、是否卷起（0/1）、折线上一点 x、y、
 * 折线法向 x、y（指向卷起一侧）、卷曲半径、阴影强度、明暗强度、纸色 r、g、b（垫在纹理透明处）、是否夜间（0/1）、
 * 纸背底色盖住正文的比例。
 */
export const render: (surfaceId: string, params: number[]) => boolean;
