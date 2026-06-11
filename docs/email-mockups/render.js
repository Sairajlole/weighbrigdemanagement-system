const puppeteer = require('puppeteer-core');
const path = require('path');
(async () => {
  const browser = await puppeteer.launch({
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: 'new',
    args: ['--allow-file-access-from-files','--no-sandbox'],
  });
  // viewport width = card(600) + wrap padding(52*2) ; height auto-captured by element screenshot
  for (const [f,name] of [['n_otp.html','otp'],['n_receipt.html','receipt'],['n_report.html','report']]) {
    const page = await browser.newPage();
    await page.setViewport({width: 704, height: 900, deviceScaleFactor: 2});
    await page.goto('file://'+path.resolve('/tmp',f), {waitUntil:'networkidle0'});
    await page.evaluate(async () => { await document.fonts.ready; });
    const el = await page.$('.wrap');
    const box = await el.boundingBox();
    await el.screenshot({path: '/tmp/P_'+name+'.png'});
    console.log(name, '->', Math.round(box.width)+'x'+Math.round(box.height), 'css (card ~600)');
    await page.close();
  }
  await browser.close();
})();
