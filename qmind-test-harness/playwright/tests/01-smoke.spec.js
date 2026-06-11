const { test, expect } = require('@playwright/test');

test('smoke-homepage-loads', async ({ page }) => {
  await page.goto('/', { waitUntil: 'domcontentloaded' });

  await expect(page.locator('body')).toContainText(/Online Boutique|Cymbal|Shop|Products/i);
});

test('smoke-product-links-visible', async ({ page }) => {
  await page.goto('/', { waitUntil: 'domcontentloaded' });

  const productLinks = page.locator('a[href*="/product"]');
  await expect(productLinks.first()).toBeVisible();

  const count = await productLinks.count();
  expect(count).toBeGreaterThan(0);
});

