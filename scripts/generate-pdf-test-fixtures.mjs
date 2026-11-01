// Original, deterministic PDF fixtures. No third-party documents or font files.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../entry/src/ohosTest/resources/rawfile/pdf');
fs.mkdirSync(root, { recursive: true });
for (const [name, pages, scanned, outline] of [
  ['text.pdf', 3, false, true], ['scan.pdf', 3, true, true],
  ['single.pdf', 1, false, false], ['long.pdf', 1000, false, false]
]) {
  const fontIndex = 3 + 2 * pages;
  const imageIndex = fontIndex + 1;
  const outlineIndex = fontIndex + 2;
  const infoIndex = fontIndex + 5;
  const objects = [null,
    `<< /Type /Catalog /Pages 2 0 R ${outline ? `/Outlines ${outlineIndex} 0 R` : ''} >>`,
    `<< /Type /Pages /Kids [${Array.from({ length: pages }, (_, i) => `${3 + 2 * i} 0 R`).join(' ')}] /Count ${pages} >>`];
  for (let i = 0; i < pages; i++) {
    objects.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 600] /Resources << /Font << /F1 ${fontIndex} 0 R >> ` +
      `/XObject << /Im1 ${imageIndex} 0 R >> >> /Contents ${4 + i * 2} 0 R >>`);
    const stream = scanned ? 'q 300 0 0 400 50 100 cm /Im1 Do Q' :
      `BT /F1 24 Tf 40 500 Td (PDF native probe page ${i + 1}) Tj ET`;
    objects.push(`<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`);
  }
  const pixels = 'ff000000ff000000ffffffff>';
  objects.push('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    `<< /Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode /Length ${pixels.length} >>\nstream\n${pixels}\nendstream`,
    `<< /Type /Outlines /First ${outlineIndex + 1} 0 R /Last ${outlineIndex + 2} 0 R /Count 2 >>`,
    `<< /Title (Opening) /Parent ${outlineIndex} 0 R /Next ${outlineIndex + 2} 0 R /Dest [3 0 R /Fit] >>`,
    `<< /Title (Final page) /Parent ${outlineIndex} 0 R /Prev ${outlineIndex + 1} 0 R /Dest [${3 + 2 * (pages - 1)} 0 R /Fit] >>`,
    '<< /Title (PDF Native Probe) /Author (Qingye Test) >>');
  let output = '%PDF-1.4\n';
  const offsets = [0];
  for (let i = 1; i < objects.length; i++) {
    offsets.push(output.length); output += `${i} 0 obj\n${objects[i]}\nendobj\n`;
  }
  const xref = output.length;
  output += `xref\n0 ${objects.length}\n0000000000 65535 f \n`;
  for (const offset of offsets.slice(1)) output += `${String(offset).padStart(10, '0')} 00000 n \n`;
  output += `trailer\n<< /Size ${objects.length} /Root 1 0 R /Info ${infoIndex} 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  const target = path.join(root, name);
  if (process.argv.includes('--check')) {
    if (!fs.existsSync(target) || fs.readFileSync(target, 'ascii') !== output) throw new Error(`Outdated PDF fixture: ${name}`);
  } else fs.writeFileSync(target, output, 'ascii');
}
