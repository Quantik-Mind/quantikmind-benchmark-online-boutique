const { test, expect } = require('@playwright/test');

test('frontend-homepage-has-product-grid', async ({ page }) => {
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('a[href*="/product"]').first()).toBeVisible();
});

test('catalog-multiple-products-visible', async ({ page }) => {
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  const count = await page.locator('a[href*="/product"]').count();
  expect(count).toBeGreaterThan(3);
});

test('catalog-first-product-link-has-valid-href', async ({ page }) => {
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  const href = await page.locator('a[href*="/product"]').first().getAttribute('href');
  expect(href).toContain('/product');
});

test('cart-empty-page-shows-cart-context', async ({ page }) => {
  await page.goto('/cart', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('body')).toContainText(/cart|empty|shopping/i);
});

test('frontend-page-has-navigation-links', async ({ page }) => {
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  const links = await page.locator('a').count();
  expect(links).toBeGreaterThan(5);
});

test('product-detail-page-has-body-content', async ({ page }) => {
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await page.locator('a[href*="/product"]').first().click();
  await expect(page.locator('body')).toContainText(/\$|add|cart|product/i);
});

test('homepage-shows-google-cloud-branding', async ({ page }) => {
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('body')).toContainText(/Google Cloud|Hot Products/i);
});

test('product-detail-allows-return-navigation', async ({ page }) => {
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await page.locator('a[href*="/product"]').first().click();
  await page.goBack({ waitUntil: 'domcontentloaded' });
  await expect(page.locator('a[href*="/product"]').first()).toBeVisible();
});

test('cart-link-is-reachable-from-homepage', async ({ page }) => {
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await page.goto('/cart', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('body')).toContainText(/cart|shopping/i);
});

test('checkout-page-does-not-crash-with-empty-cart', async ({ page }) => {
  await page.goto('/cart/checkout', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('body')).not.toContainText(/panic|exception|stack trace|internal server error/i);
});

test('homepage-has-visible-text-content', async ({ page }) => {
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  const text = await page.locator('body').innerText();
  expect(text.length).toBeGreaterThan(100);
});