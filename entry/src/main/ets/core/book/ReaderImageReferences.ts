import { ReaderImageMarker } from './ReaderImageMarker';
import { ReaderCacheCoordinator } from './ReaderCacheCoordinator';

/** Shared by DB indexing, migration and cache validation; never treats arbitrary text as a file. */
export class ReaderImageReferences {
  static markers(text: string): string[] {
    return text.match(/\[\[LEGADO_EPUB_IMAGE:[^\]]+\]\]/g) || [];
  }

  static paths(text: string): string[] {
    const paths: Set<string> = new Set();
    for (const marker of ReaderImageReferences.markers(text)) {
      const path = ReaderCacheCoordinator.path(ReaderImageMarker.parse(marker).source);
      if (path.startsWith('/')) paths.add(path);
    }
    return Array.from(paths);
  }

  static replace(text: string, previous: string, next: string): string {
    return text.replace(/\[\[LEGADO_EPUB_IMAGE:[^\]]+\]\]/g, (marker: string): string => {
      const info = ReaderImageMarker.parse(marker);
      return ReaderCacheCoordinator.path(info.source) === previous ?
        ReaderImageMarker.create(next, info.width, info.height) : marker;
    });
  }
}
