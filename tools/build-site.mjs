/* ==========================================================================
   mpv-redesigned - site build
   --------------------------------------------------------------------------
   The published site is a single static file, because GitHub Pages serves
   exactly that and the page has to survive every CDN being blocked. But
   writing a 1500 line HTML file by hand is how a page stops being a
   document, so the source is split into a layout and one partial per
   section and this script assembles them.

       node tools/build-site.mjs

   The result, site/index.html, is committed. Pages serves it directly, so
   there is no build step in the deployment at all.
   ========================================================================== */
import { readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..');
const site = resolve(root, 'site');

const SECTIONS = [
  ['hero', '01-hero'],
  ['features', '02-features'],
  ['inside', '03-inside'],
  ['showcase', '04-showcase'],
  ['deep', '05-deep'],
  ['keys', '06-keys'],
  ['install', '07-install'],
  ['faq', '08-faq']
];

const layout = await readFile(resolve(site, 'src/layout.html'), 'utf8');

if (!layout.includes('<!--SECTIONS-->')) {
  throw new Error('site/src/layout.html is missing the <!--SECTIONS--> marker');
}

const parts = [];
for (const [, name] of SECTIONS) {
  const file = resolve(site, 'partials', `${name}.html`);
  const body = await readFile(file, 'utf8');
  parts.push(body.trim());
}

const html = layout.replace('<!--SECTIONS-->', parts.join('\n\n'));

if (html.includes('<!--SECTIONS-->')) {
  throw new Error('the section marker was not replaced');
}

await writeFile(resolve(site, 'index.html'), html, 'utf8');
console.log(`site/index.html written (${html.length} bytes, ${SECTIONS.length} sections)`);
