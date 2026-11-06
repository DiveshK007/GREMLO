// One real 0G call. Prints the request ID, or the real error if there is none.
import { think } from '../index.js';

const out = await think({ event: 'UserPromptSubmit', mood: 'stable' });
if (out.requestId) console.log(`request_id ${out.requestId}`);
console.log(JSON.stringify(out));
process.exit(out.action === 'sleep' ? 1 : 0);
