/** Only the host-generated document may use a data: navigation in the offline comment Web. */
export class NativeCommentDocumentPolicy {
  static allowsNavigation(url: string, mainFrame: boolean, documentBase64: string): boolean {
    if (url === 'about:blank' || url === 'about:srcdoc') return true;
    if (!mainFrame || !documentBase64) return false;
    const comma = url.indexOf(',');
    if (comma < 0) return false;
    const header = url.substring(0, comma);
    return /^data:text\/html(?:;charset=[a-z0-9_-]+)?;base64$/i.test(header) &&
      url.substring(comma + 1) === documentBase64;
  }

  static allowsResource(url: string, mainFrame: boolean, documentBase64: string): boolean {
    return NativeCommentDocumentPolicy.allowsNavigation(url, mainFrame, documentBase64) ||
      /^data:image\//i.test(url);
  }
}
