/** Immutable object keys: replacing a model requires a new hash and a compatible app release. */
export const COMIC_COLOR_MODELS = [
  { file: 'alac.ms', bytes: 61596264, sha256: 'c212815a335a006b4bbf336af1c25c6158aaeac077f35f2775af381b83fe9934' },
  { file: 'alac-npu-portrait.ms', bytes: 61608728, sha256: 'db162d1620a560c86fe883484311133e11ba5e4b24790cefe355043f9928e3e0' },
  { file: 'alac-npu-landscape.ms', bytes: 61608728, sha256: '2abbc0e27cb1dbf859a835072c4c7f06982e70cd0e57ff401008501b33ce40fd' }
] as const;

export function comicColorObjectKey(model: typeof COMIC_COLOR_MODELS[number]): string {
  return `qingye/ai/comic-colorizer/${model.sha256}/${model.file}`;
}
