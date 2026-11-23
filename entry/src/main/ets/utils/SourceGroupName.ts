/**
 * 书源分组名的统一规整：去首尾空白；整个名字只由看不见的字符组成（零宽字符、韩文填充符、盲文空格等，
 * trim 不会去掉它们）时当作未分组，否则分组管理里会出现一个名字空白的分组。
 * 数据库读写书源时都经过这里，页面拿到的分组名不需要再各自判断。
 */
export class SourceGroupName {
  private static readonly INVISIBLE: RegExp =
    /[\s\u0000-\u001F\u007F-\u009F\u00AD\u034F\u061C\u115F\u1160\u17B4\u17B5\u180B-\u180F\u200B-\u200F\u202A-\u202E\u2060-\u206F\u2800\u3164\uFE00-\uFE0F\uFEFF\uFFA0\uFFF9-\uFFFC]/g;

  static clean(name: string | null | undefined): string {
    const text = (name || '').trim();
    if (!text) return '';
    return text.replace(SourceGroupName.INVISIBLE, '') ? text : '';
  }
}
