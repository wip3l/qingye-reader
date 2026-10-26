import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import { AccountCommerceApi } from './AccountCommerceApi';
import { AccountSessionStore } from './AccountSessionStore';

class ComicColorDownloadTicket {
  url: string = '';
  bytes: number = 0;
}

export class ComicColorModelDownload {
  static async download(file: string, destination: string, bytes: number, active: () => boolean,
    progress: (received: number) => void): Promise<void> {
    if (!active()) throw new Error('已取消模型下载');
    const ticket = JSON.parse(await AccountCommerceApi.colorModelTicket(file,
      AccountSessionStore.token())) as ComicColorDownloadTicket;
    if (ticket.bytes !== bytes || !/^https:\/\//i.test(ticket.url)) throw new Error('模型下载信息无效');
    if (!active()) throw new Error('已取消模型下载');
    const output = await fs.open(destination, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    const client = http.createHttp();
    let received = 0;
    let failure = '';
    let timer = -1;
    try {
      await new Promise<void>((resolve, reject): void => {
        let ended = false;
        let accepted = false;
        const fail = (message: string): void => {
          if (failure) return;
          failure = message;
          reject(new Error(message));
          try { client.destroy(); } catch (_) {}
        };
        const complete = (): void => {
          if (ended && accepted && !failure) {
            if (received !== bytes) fail('模型下载不完整，请重试');
            else resolve();
          }
        };
        client.on('dataReceive', (chunk: ArrayBuffer): void => {
          if (failure) return;
          if (!active()) { fail('已取消模型下载'); return; }
          if (received + chunk.byteLength > bytes) { fail('模型大小异常'); return; }
          try {
            let offset = 0;
            while (offset < chunk.byteLength) {
              const count = fs.writeSync(output.fd, chunk.slice(offset));
              if (count <= 0) throw new Error('写入失败');
              offset += count;
            }
            received += chunk.byteLength;
            progress(received);
          } catch (_) { fail('无法保存模型，请检查存储空间后重试'); }
        });
        client.on('dataEnd', (): void => { ended = true; complete(); });
        const deadline = Date.now() + 15 * 60 * 1000;
        timer = setInterval((): void => {
          if (!active()) fail('已取消模型下载');
          else if (Date.now() > deadline) fail('模型下载超时，请重试');
        }, 200);
        // Never forward the account token to OBS. The short-lived URL is the only credential.
        client.requestInStream(ticket.url, { method: http.RequestMethod.GET,
          connectTimeout: 20000, readTimeout: 120000, usingProxy: false })
          .then((status: number): void => {
            if (status !== 200) { fail('模型下载失败，请稍后重试'); return; }
            accepted = true;
            complete();
          }).catch((): void => { fail('模型下载失败，请检查网络后重试'); });
      });
    } finally {
      if (timer >= 0) clearInterval(timer);
      try { client.off('dataReceive'); client.off('dataEnd'); client.destroy(); } catch (_) {}
      await fs.close(output);
    }
  }
}
