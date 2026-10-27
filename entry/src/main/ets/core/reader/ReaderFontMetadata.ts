/** Small, bounded SFNT reads; never load a whole imported font to inspect its weight axis. */
export class ReaderFontMetadata {
  known: boolean = false;
  variableWeight: boolean = false;
  weight: number = 400;
  minWeight: number = 50;
  maxWeight: number = 900;

  static inspect(size: number, read: (offset: number, length: number) => Uint8Array): ReaderFontMetadata {
    const info = new ReaderFontMetadata();
    if (size < 12) return info;
    const header = read(0, 12);
    if (header.length !== 12) return info;
    const tag = ReaderFontMetadata.tag(header, 0);
    // A collection can contain multiple faces/weights. Leave its native matching intact.
    if (tag !== 'OTTO' && ReaderFontMetadata.u32(header, 0) !== 0x00010000) return info;
    const count = ReaderFontMetadata.u16(header, 4);
    if (count < 1 || count > 4096 || 12 + count * 16 > size) return info;
    const directory = read(12, count * 16);
    if (directory.length !== count * 16) return info;
    for (let index = 0; index < count; index++) {
      const record = index * 16;
      const offset = ReaderFontMetadata.u32(directory, record + 8);
      const length = ReaderFontMetadata.u32(directory, record + 12);
      if (offset > size || length > size - offset) return new ReaderFontMetadata();
      const table = ReaderFontMetadata.tag(directory, record);
      if (table === 'OS/2' && length >= 6) {
        const data = read(offset, 6);
        if (data.length !== 6) return new ReaderFontMetadata();
        info.weight = Math.max(1, Math.min(1000, ReaderFontMetadata.u16(data, 4)));
      }
      if (table !== 'fvar') continue;
      if (length < 16) return new ReaderFontMetadata();
      const axisHeader = read(offset, 16);
      if (axisHeader.length !== 16) return new ReaderFontMetadata();
      const axesOffset = ReaderFontMetadata.u16(axisHeader, 4);
      const axesCount = ReaderFontMetadata.u16(axisHeader, 8);
      const axisSize = ReaderFontMetadata.u16(axisHeader, 10);
      if (axesOffset < 16 || axisSize < 20 || axesCount > 64 ||
        axesOffset + axesCount * axisSize > length) return new ReaderFontMetadata();
      for (let axis = 0; axis < axesCount; axis++) {
        const data = read(offset + axesOffset + axis * axisSize, 20);
        if (data.length !== 20) return new ReaderFontMetadata();
        if (ReaderFontMetadata.tag(data, 0) !== 'wght') continue;
        const min = ReaderFontMetadata.fixed(data, 4);
        const max = ReaderFontMetadata.fixed(data, 12);
        if (min <= 0 || max < min) return new ReaderFontMetadata();
        info.variableWeight = true;
        info.minWeight = min;
        info.maxWeight = max;
      }
    }
    info.known = true;
    return info;
  }

  private static tag(data: Uint8Array, offset: number): string {
    return String.fromCharCode(data[offset], data[offset + 1], data[offset + 2], data[offset + 3]);
  }

  private static u16(data: Uint8Array, offset: number): number {
    return data[offset] * 256 + data[offset + 1];
  }

  private static u32(data: Uint8Array, offset: number): number {
    return ReaderFontMetadata.u16(data, offset) * 65536 + ReaderFontMetadata.u16(data, offset + 2);
  }

  private static fixed(data: Uint8Array, offset: number): number {
    return (ReaderFontMetadata.u32(data, offset) | 0) / 65536;
  }
}
