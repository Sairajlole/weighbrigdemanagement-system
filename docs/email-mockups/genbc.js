const bwipjs = require('bwip-js'); const fs = require('fs');
(async () => {
  const png = await bwipjs.toBuffer({
    bcid: 'pdf417',
    text: 'TULANAM|RST-1042|MH12AB1234|NET:28000KG|GRS:42000|TAR:14000|2026-06-11T15:42|ABCWB',
    columns: 10, scale: 3, backgroundcolor: 'FFFFFF',
    paddingwidth: 2, paddingheight: 2,
  });
  fs.writeFileSync('/tmp/pdf417.png', png);
  console.log('pdf417.png', png.length, 'bytes');
})();
