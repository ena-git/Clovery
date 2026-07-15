const fs = require('node:fs');
const path = require('node:path');

const repositoryRoot = path.resolve(__dirname, '..');
const htmlPath = path.join(repositoryRoot, 'Clovery', 'Clover Diary.html');
const babelPath = path.join(repositoryRoot, 'Clovery', 'vendor', 'babel.min.js');
const Babel = require(babelPath);
const html = fs.readFileSync(htmlPath, 'utf8');
const scripts = [...html.matchAll(/<script\s+type=["']text\/babel["'][^>]*>([\s\S]*?)<\/script>/gi)];

if (scripts.length === 0) {
  throw new Error('No text/babel scripts found');
}

scripts.forEach((match, index) => {
  Babel.transform(match[1], {
    filename: `inline-${index + 1}.jsx`,
    presets: ['react'],
    sourceType: 'script',
  });
});

process.stdout.write(`Validated ${scripts.length} Babel scripts\n`);
