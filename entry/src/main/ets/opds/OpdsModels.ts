// OPDS 目录数据模型。纯数据类，无平台 API 依赖，供解析器、客户端与页面共用。

export const OPDS_ACQUISITION_REL_PREFIX: string = 'http://opds-spec.org/acquisition';
export const OPDS_IMAGE_REL: string = 'http://opds-spec.org/image';
export const OPDS_IMAGE_THUMBNAIL_REL: string = 'http://opds-spec.org/image/thumbnail';
// OPDS 1.0 及 Stanza 时代的旧式封面 rel，旧版 Calibre-Web、COPS 等仍在使用。
const OPDS_IMAGE_RELS: string[] = [OPDS_IMAGE_REL, 'http://opds-spec.org/cover', 'x-stanza-cover-image'];
const OPDS_IMAGE_THUMBNAIL_RELS: string[] = [OPDS_IMAGE_THUMBNAIL_REL, 'http://opds-spec.org/thumbnail',
  'x-stanza-cover-image-thumbnail'];
export const OPDS_CATALOG_FEED_TYPE: string = 'application/atom+xml;profile=opds-catalog';
export const OPDS_CATALOG_ENTRY_TYPE: string =
  'application/atom+xml;type=entry;profile=opds-catalog';
export const OPDS_SEARCH_DESCRIPTION_TYPE: string = 'application/opensearchdescription+xml';

export function opdsFormatOfType(type: string): string {
  const value = (type || '').split(';')[0].trim().toLowerCase();
  if (value === 'application/epub+zip') return 'epub';
  if (value === 'text/plain') return 'txt';
  if (value === 'application/pdf') return 'pdf';
  if (value === 'application/x-mobipocket-ebook') return 'mobi';
  if (value === 'application/vnd.amazon.mobi8-ebook' || value === 'application/azw3') return 'azw3';
  if (value === 'application/x-fictionbook+xml' || value === 'application/x-fictionbook' ||
    value === 'text/fb2+xml') return 'fb2';
  if (value === 'application/fb2+zip' || value === 'application/x-zip-compressed-fb2') return 'fbz';
  if (value === 'application/x-cbz' || value === 'application/vnd.comicbook+zip') return 'cbz';
  if (value === 'application/x-cbr' || value === 'application/vnd.comicbook-rar') return 'cbr';
  return '';
}

export class OpdsLink {
  href: string = '';
  rel: string = '';
  type: string = '';
  title: string = '';
  length: number = 0;
  price: string = '';
  priceCurrency: string = '';
  facetGroup: string = '';
  activeFacet: boolean = false;
  facetCount: number = 0;
  pseCount: number = 0;
  pseLastRead: number = 0;
  indirectTypes: string[] = [];

  isAcquisition(): boolean {
    const rel = (this.rel || '').trim().toLowerCase();
    return rel.startsWith(OPDS_ACQUISITION_REL_PREFIX);
  }

  acquisitionKind(): string {
    if (!this.isAcquisition()) return '';
    const suffix = (this.rel || '').trim().substring(OPDS_ACQUISITION_REL_PREFIX.length);
    if (suffix.startsWith('/')) return suffix.substring(1).trim().toLowerCase();
    return 'generic';
  }

  isCatalogFeed(): boolean {
    return (this.type || '').toLowerCase().indexOf('profile=opds-catalog') >= 0 &&
      (this.type || '').toLowerCase().indexOf('type=entry') < 0;
  }

  isCatalogEntry(): boolean {
    return (this.type || '').toLowerCase().indexOf('type=entry') >= 0 &&
      (this.type || '').toLowerCase().indexOf('profile=opds-catalog') >= 0;
  }

  isSearchDescription(): boolean {
    return (this.type || '').trim().toLowerCase() === OPDS_SEARCH_DESCRIPTION_TYPE;
  }
}

export class OpdsEntry {
  id: string = '';
  title: string = '';
  updated: string = '';
  authors: string[] = [];
  summary: string = '';
  summaryIsHtml: boolean = false;
  content: string = '';
  contentIsHtml: boolean = false;
  categories: string[] = [];
  language: string = '';
  publisher: string = '';
  series: string = '';
  links: OpdsLink[] = [];

  acquisitionLinks(): OpdsLink[] {
    return this.links.filter((link: OpdsLink): boolean => link.isAcquisition());
  }

  navigationLink(): OpdsLink | null {
    for (const link of this.links) {
      if (link.isAcquisition() || link.isSearchDescription()) continue;
      if (link.isCatalogFeed()) return link;
    }
    for (const link of this.links) {
      const rel = (link.rel || '').trim().toLowerCase();
      if (rel === 'subsection' || rel === 'related' || rel === 'alternate') continue;
      if ((link.type || '').indexOf('atom+xml') >= 0) return link;
    }
    return null;
  }

  alternateEntryLink(): OpdsLink | null {
    for (const link of this.links) {
      if (link.rel !== 'alternate') continue;
      if (link.isCatalogEntry()) return link;
    }
    return null;
  }

  artworkThumbnail(): string {
    return this.firstLinkOfRels(OPDS_IMAGE_THUMBNAIL_RELS) || this.artworkImage();
  }

  artworkImage(): string {
    return this.firstLinkOfRels(OPDS_IMAGE_RELS);
  }

  private firstLinkOfRels(rels: string[]): string {
    for (const rel of rels) {
      for (const link of this.links) {
        if (link.href && (link.rel || '').trim().toLowerCase() === rel) return link.href;
      }
    }
    return '';
  }

  isPublication(): boolean {
    return this.acquisitionLinks().length > 0;
  }

  displayAuthor(): string {
    return this.authors.join(', ');
  }

  displayText(): string {
    if (this.content) return this.content;
    return this.summary;
  }
}

export class OpdsFacetGroup {
  group: string = '';
  links: OpdsLink[] = [];
}

export class OpdsFeed {
  id: string = '';
  title: string = '';
  subtitle: string = '';
  updated: string = '';
  logoUrl: string = '';
  links: OpdsLink[] = [];
  entries: OpdsEntry[] = [];
  totalResults: number = -1;
  itemsPerPage: number = -1;

  searchLink(): OpdsLink | null {
    for (const link of this.links) {
      if ((link.rel || '').trim().toLowerCase() === 'search') return link;
    }
    return null;
  }

  nextLink(): OpdsLink | null {
    for (const link of this.links) {
      if ((link.rel || '').trim().toLowerCase() === 'next') return link;
    }
    return null;
  }

  facetGroups(): OpdsFacetGroup[] {
    const groups: OpdsFacetGroup[] = [];
    for (const link of this.links) {
      if (!link.facetGroup) continue;
      let group = groups.find((item: OpdsFacetGroup): boolean => item.group === link.facetGroup);
      if (!group) {
        group = new OpdsFacetGroup();
        group.group = link.facetGroup;
        groups.push(group);
      }
      group.links.push(link);
    }
    return groups;
  }

  isNavigationFeed(): boolean {
    for (const entry of this.entries) {
      if (entry.isPublication()) return false;
    }
    for (const entry of this.entries) {
      if (entry.navigationLink()) return true;
    }
    return this.entries.length === 0;
  }
}

export class OpdsSearchTemplate {
  urlTemplate: string = '';
  indexOffset: number = 1;
  pageOffset: number = 1;
}

export class OpdsServerConfig {
  id: string = '';
  name: string = '';
  baseUrl: string = '';
  authType: string = 'none';
  username: string = '';
  rememberPassword: boolean = true;
  enabled: boolean = true;
  createdAt: number = 0;
  updatedAt: number = 0;
}

export class OpdsFeedCacheEntry {
  feed: OpdsFeed = new OpdsFeed();
  fetchedAt: number = 0;
}
