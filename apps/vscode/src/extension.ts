import * as vscode from "vscode";
import { createConnection } from "node:net";
import { homedir } from "node:os";
import { join } from "node:path";

// R4 §16: the pet in VS Code and Cursor. Talks to the Mac app over its local socket; if the app isn't running it
// says so and does nothing else. Never shows the sponsored line: that stays on the plate in the notch.

const SOCKET = join(homedir(), "Library/Application Support/Notchi/notchi.sock");
type Reply = { ok: boolean; text: string; data?: Record<string, string> };

function send(cmd: string, args: Record<string, string> = {}): Promise<Reply | null> {
  return new Promise((resolve) => {
    let buf = "";
    const c = createConnection(SOCKET, () => c.write(JSON.stringify({ cmd, args }) + "\n"));
    c.setTimeout(3000, () => { c.destroy(); resolve(null); });
    c.on("data", (d) => (buf += d.toString()));
    c.on("end", () => { try { resolve(JSON.parse(buf)); } catch { resolve(null); } });
    c.on("error", () => resolve(null));
  });
}

let bar: vscode.StatusBarItem;
let panel: vscode.WebviewPanel | undefined;
const asked = new Set<string>(); // approvals already shown, so one isn't asked twice

export function activate(ctx: vscode.ExtensionContext) {
  bar = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
  bar.command = "notchi.openPanel";
  bar.show();
  ctx.subscriptions.push(bar,
    vscode.commands.registerCommand("notchi.openPanel", () => openPanel(ctx)),
    vscode.commands.registerCommand("notchi.answerNext", () => answer()));
  const timer = setInterval(tick, 2000);
  ctx.subscriptions.push({ dispose: () => clearInterval(timer) });
  void tick();
}

async function tick() {
  const s = await send("status");
  if (!s?.data) { bar.text = "$(circle-slash) Notchi isn't running"; bar.tooltip = undefined; panel?.webview.postMessage({ off: true }); return; }
  const d = s.data;
  bar.text = `$(smiley) ${d.pet} · ${d.mood}${d.running === "1" ? ` · ${d.tools} tools` : ""}${d.approvals !== "0" ? ` · ${d.approvals} waiting` : ""}`;
  bar.tooltip = s.text;
  panel?.webview.postMessage({ mood: d.mood, running: d.running === "1", waiting: Number(d.approvals) });
  if (d.approvals !== "0") await answer(true);
}

/** Ordinary approvals can be answered here; one answered anywhere disappears everywhere. Risky ones need the notch. */
async function answer(onlyNew = false) {
  const a = await send("approvals");
  const n = Number(a?.data?.count ?? 0);
  for (let i = 0; i < Math.min(n, 4); i++) {
    const id = a!.data![`${i}.id`], tool = a!.data![`${i}.tool`], summary = a!.data![`${i}.summary`], risky = a!.data![`${i}.risky`] === "1";
    if (onlyNew && asked.has(id)) continue;
    asked.add(id);
    if (risky) { void vscode.window.showWarningMessage(`Notchi: ${tool} wants to run "${summary}". It deletes, pushes or spends: answer on the Mac.`); continue; }
    void vscode.window.showInformationMessage(`Notchi: ${tool} wants to run "${summary}"`, "Allow once", "Deny").then(async (pick) => {
      if (!pick) return;
      const r = await send("approve", { id, answer: pick === "Deny" ? "deny" : "allow" });
      if (r && !r.ok) void vscode.window.showInformationMessage(`Notchi: ${r.text}`);
    });
    if (!onlyNew) return;
  }
}

function openPanel(ctx: vscode.ExtensionContext) {
  if (panel) { panel.reveal(); return; }
  panel = vscode.window.createWebviewPanel("notchi", "Notchi", vscode.ViewColumn.Beside, {
    enableScripts: true, localResourceRoots: [vscode.Uri.joinPath(ctx.extensionUri, "media")],
  });
  const sheet = panel.webview.asWebviewUri(vscode.Uri.joinPath(ctx.extensionUri, "media", "notchi.webp"));
  const csp = `default-src 'none'; img-src ${panel.webview.cspSource}; style-src 'unsafe-inline'; script-src 'unsafe-inline'`;
  panel.webview.html = `<!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="${csp}"><style>
  body{margin:0;height:100vh;overflow:hidden;background:transparent;font:13px system-ui;color:var(--vscode-foreground)}
  #pet{position:absolute;bottom:8px;left:0;width:96px;height:104px;background:url(${sheet}) no-repeat;background-size:768px 4056px;image-rendering:pixelated}
  #msg{position:absolute;top:12px;left:12px;opacity:.7}</style></head><body><div id="msg"></div><div id="pet"></div><script>
  const pet=document.getElementById('pet'),msg=document.getElementById('msg');let x=20,dir=1,f=0,row=1,running=false;
  addEventListener('message',e=>{const d=e.data;if(d.off){msg.textContent="Notchi isn't running";row=26;return}
    msg.textContent=d.waiting?d.waiting+' waiting on you':(d.running?'working':d.mood);running=d.running;row=d.waiting?7:(d.mood==='asleep'?26:1)});
  setInterval(()=>{f=(f+1)%(row===1?8:4);if(row===1){x+=dir*(running?3:1.5);if(x>innerWidth-100||x<0)dir*=-1}
    pet.style.left=x+'px';pet.style.transform=dir<0?'scaleX(-1)':'';pet.style.backgroundPosition=(-f*96)+'px '+(-row*104)+'px'},125);
  </script></body></html>`;
  panel.onDidDispose(() => (panel = undefined));
}

export function deactivate() {}
