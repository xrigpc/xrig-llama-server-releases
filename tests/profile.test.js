const {execFileSync} = require('child_process');
const path = require('path');
const root = path.resolve(__dirname, '..');
execFileSync('node', ['scripts/profile.js', 'profiles/rx7900xtx-rocm-gfx1100.yaml'], {cwd: root, stdio:'inherit'});
const p = JSON.parse(require('fs').readFileSync(path.join(root, 'profiles/rx7900xtx-rocm-gfx1100.yaml')));
if (p.source.commit.length !== 40 || !p.asset_prefix.includes(p.lane_id)) throw new Error('naming/source contract regression');
console.log('profile contract passed');
