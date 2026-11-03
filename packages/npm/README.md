# @chiplab/core

WebAssembly core for the ChipLab ITCH-50 silicon lab.

```js
import { loadCore, decodeRecord, CHIPS } from "@chiplab/core";

const core = await loadCore(new URL("@chiplab/core/wasm", import.meta.url));
const stream = core.generate(100_000, 0, 1337);
const run = core.run(1, stream);
console.log(run.header.count, run.header.cycles);
```

Node, no fetch:

```js
import { loadCoreFromFile } from "@chiplab/core";
const core = await loadCoreFromFile("./node_modules/@chiplab/core/wasm/chiplab_core.wasm");
```

CLI:

```bash
npx chiplab --compare --count 100000
npx chiplab --chip 1 --count 1000000
```

The WASM is deterministic and runs locally. Latency numbers are model cycles at
322.26 MHz; they are not silicon measurements. See the repository README for the
full honesty statement.
