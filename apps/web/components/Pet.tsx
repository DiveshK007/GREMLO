"use client";

import { forwardRef, useEffect, useImperativeHandle, useRef } from "react";
import { FRAMES, ROW, sheetUrl, speciesOf, type RowName, type Species } from "@/lib/species";

// One canvas per pet, all driven by a single animation frame loop; nearest-neighbour so the pixels stay square.
// Reduced motion holds frame 0 of each row.

const sheets = new Map<string, HTMLImageElement | null>();
const waiting = new Map<string, Promise<void>>();
function sheet(s: Species) {
  if (!waiting.has(s.id)) {
    waiting.set(s.id, new Promise((res) => {
      const i = new Image();
      i.onload = () => { sheets.set(s.id, i); res(); };
      i.onerror = () => { sheets.set(s.id, null); res(); };
      i.src = sheetUrl(s);
    }));
  }
  return waiting.get(s.id)!;
}

type Play = { row: number; frames?: number[]; fps?: number; loop?: boolean; onEnd?: () => void };
class Sprite {
  sp: Species;
  row = ROW.idle as number;
  frames: number[] = [0];
  fps = 6;
  loop = true;
  t0 = 0;
  fixed: number | null = null;
  onEnd: (() => void) | null = null;
  last = "";
  constructor(public cv: HTMLCanvasElement, sp: Species, public scale: number) { this.sp = sp; this.size(); }
  size() {
    const d = Math.min(2, window.devicePixelRatio || 1);
    this.cv.width = Math.round(192 * this.scale * d);
    this.cv.height = Math.round(208 * this.scale * d);
    this.cv.style.width = `${192 * this.scale}px`;
    this.cv.style.height = `${208 * this.scale}px`;
    this.last = "";
  }
  play(p: Play) {
    this.row = p.row; this.frames = p.frames ?? [...Array(FRAMES[p.row]).keys()]; this.fps = p.fps ?? 6; this.loop = p.loop !== false;
    this.onEnd = p.onEnd ?? null; this.fixed = null; this.t0 = performance.now(); this.last = "";
  }
  show(row: number, frame: number) { this.row = row; this.fixed = frame; this.onEnd = null; this.last = ""; }
  tick(now: number, still: boolean) {
    let f: number;
    if (this.fixed != null) f = this.fixed;
    else {
      let i = still ? 0 : Math.floor(((now - this.t0) / 1000) * this.fps);
      if (!this.loop && i >= this.frames.length) {
        i = this.frames.length - 1;
        if (this.onEnd) { const cb = this.onEnd; this.onEnd = null; cb(); }
      }
      f = this.frames[i % this.frames.length];
    }
    const img = sheets.get(this.sp.id);
    const key = `${this.sp.id}.${this.row}.${f}`;
    if (!img || key === this.last) return;
    this.last = key;
    const c = this.cv.getContext("2d")!;
    c.setTransform(1, 0, 0, 1, 0, 0);
    c.clearRect(0, 0, this.cv.width, this.cv.height);
    c.imageSmoothingEnabled = false;
    c.drawImage(img, f * 192, this.row * 208, 192, 208, 0, 0, this.cv.width, this.cv.height);
  }
}

const live = new Set<Sprite>();
let running = false;
function start() {
  if (running) return;
  running = true;
  const still = window.matchMedia("(prefers-reduced-motion: reduce)");
  const loop = (now: number) => {
    for (const s of live) s.tick(now, still.matches);
    if (live.size) requestAnimationFrame(loop);
    else running = false;
  };
  requestAnimationFrame(loop);
}

export type PetHandle = { play: (row: RowName, o?: Omit<Play, "row">) => void; show: (row: RowName, frame: number) => void };
type Props = {
  species?: string | null;
  row?: RowName;
  fps?: number;
  frames?: number[];
  /** hold one frame instead of animating */
  frame?: number;
  scale?: number;
  className?: string;
  style?: React.CSSProperties;
  /** set only when the pet is the content (an image someone should hear about); otherwise it's decorative */
  label?: string;
};

export const Pet = forwardRef<PetHandle, Props>(function Pet({ species, row = "idle", fps = 6, frames, frame, scale = 0.5, className, style, label }, ref) {
  const cv = useRef<HTMLCanvasElement>(null);
  const sprite = useRef<Sprite | null>(null);
  const sp = speciesOf(species);
  const framesKey = frames?.join(",");

  useEffect(() => {
    const s = new Sprite(cv.current!, sp, scale);
    sprite.current = s;
    live.add(s);
    void sheet(sp).then(() => { s.last = ""; });
    start();
    return () => { live.delete(s); };
    // a new species or scale is a new sprite; row and timing changes are applied below
  }, [sp.id, scale]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    const s = sprite.current;
    if (!s) return;
    if (frame != null) s.show(ROW[row], frame);
    else s.play({ row: ROW[row], fps, frames });
  }, [sp.id, scale, row, fps, framesKey, frame]); // eslint-disable-line react-hooks/exhaustive-deps

  useImperativeHandle(ref, () => ({
    play: (r, o) => sprite.current?.play({ ...o, row: ROW[r] }),
    show: (r, f) => sprite.current?.show(ROW[r], f),
  }), []);

  return label
    ? <canvas ref={cv} className={className} style={style} role="img" aria-label={label} />
    : <canvas ref={cv} className={className} style={style} aria-hidden="true" />;
});
