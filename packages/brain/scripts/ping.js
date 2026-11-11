// One real NEAR AI call. Prints the completion id (verifiable at cloud.near.ai/verify), or the real error.
import { think } from '../index.js';

const out = await think({ event: 'UserPromptSubmit', mood: 'stable' });
if (out.requestId) console.log(`completion_id ${out.requestId}`);
console.log(JSON.stringify(out));
process.exit(out.action === 'sleep' ? 1 : 0);
