/* A smoke test for the assembled page: balanced markup, and every id the
   JavaScript looks for actually being there. Run with `node tools/check-site.mjs`. */
import { readFile } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const site = resolve(here, '..', 'site');

const html = await readFile(resolve(site, 'index.html'), 'utf8');
const js = await readFile(resolve(site, 'assets/js/main.js'), 'utf8');

let failed = false;
const fail = (m) => { console.error('FAIL ' + m); failed = true; };

/* 1. balanced markup */
const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input',
  'link', 'meta', 'param', 'source', 'track', 'wbr']);
const stripped = html
  .replace(/<!--[\s\S]*?-->/g, '')
  .replace(/<script[\s\S]*?<\/script>/gi, '')
  .replace(/<style[\s\S]*?<\/style>/gi, '');

const stack = [];
const tagRe = /<(\/?)([a-zA-Z][a-zA-Z0-9]*)\b[^>]*?(\/?)>/g;
let m;
while ((m = tagRe.exec(stripped)) !== null) {
  const [, closing, name, selfClose] = m;
  if (VOID.has(name.toLowerCase()) || selfClose === '/') continue;
  if (!closing) {
    stack.push(name.toLowerCase());
  } else {
    const open = stack.pop();
    if (open !== name.toLowerCase()) {
      fail(`markup: </${name}> closes <${open}>`);
      break;
    }
  }
}
if (stack.length) fail('markup: unclosed ' + stack.join(', '));

/* 2. every id the javascript looks for */
const ids = [...js.matchAll(/\$\('#([a-zA-Z0-9_-]+)'\)/g)].map((x) => x[1]);
const unique = [...new Set(ids)];
const missing = unique.filter((id) => !new RegExp(`id="${id}"`).test(html));
if (missing.length) fail('missing ids: ' + missing.join(', '));

/* 3. the scroll spy: every data-spy must name a real section */
const spies = [...html.matchAll(/data-spy="([^"]+)"/g)].map((x) => x[1]);
const badSpy = spies.filter((s) => !new RegExp(`id="${s}"`).test(html));
if (badSpy.length) fail('data-spy points at nothing: ' + [...new Set(badSpy)].join(', '));

/* 4. tab buttons and panels must line up */
for (const group of html.split('data-tabs').slice(1)) {
  const buttons = [...group.matchAll(/data-tab="(\d+)"/g)].map((x) => x[1]);
  const panels = [...group.matchAll(/data-tab-panel="(\d+)"/g)].map((x) => x[1]);
  if (buttons.join(',') !== panels.join(',')) {
    fail('tab order mismatch: buttons [' + buttons + '] panels [' + panels + ']');
  }
}

/* 5. copy buttons carry both halves of the contract */
const copies = [...html.matchAll(/<button[^>]*data-copy="([^"]*)"[^>]*>([\s\S]*?)<\/button>/g)];
for (const [, value, inner] of copies) {
  if (!inner.includes('data-copy-label')) fail('copy button without a label child');
  if (!value.trim()) fail('copy button with an empty command');
}
if (!copies.length) fail('no copy buttons found');

/* 6. the alpine names are strings, so they cannot be renamed by accident */
for (const name of ['siteNav', 'tabSet', 'bindingsPanel']) {
  if (!html.includes(`x-data="${name}"`)) fail('no x-data="' + name + '" in the markup');
}
for (const method of ['toggle()', 'close()', 'select(', 'setQuery(', 'mountAnt()']) {
  if (!html.includes(method)) fail('markup never calls ' + method);
}

/* 7. nothing white, nothing invisible on paper */
if (/[\w-]+-white\//.test(html)) fail('a white utility survived; it is invisible on paper');

/* 8. the figures are numbered */
const plates = [...html.matchAll(/<b>(PLATE \d+)<\/b>/g)].map((x) => x[1]);
if (plates.length < 4) fail('expected at least four numbered plates, found ' + plates.length);

console.log(
  failed
    ? 'site check FAILED'
    : `site check passed: ${unique.length} ids, ${copies.length} copy buttons, ${plates.length} plates`
);
process.exit(failed ? 1 : 0);
