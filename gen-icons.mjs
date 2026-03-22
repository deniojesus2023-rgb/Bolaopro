import sharp from 'sharp';
import { readFileSync } from 'fs';

const svg = readFileSync('./logo-mark.svg');

await sharp(svg).resize(192, 192).png().toFile('./icon-192.png');
console.log('icon-192.png ✓');

await sharp(svg).resize(512, 512).png().toFile('./icon-512.png');
console.log('icon-512.png ✓');
