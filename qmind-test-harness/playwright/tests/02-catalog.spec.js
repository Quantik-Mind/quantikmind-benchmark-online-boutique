const { test, expect } = require('@playwright/test');

test('catalog-open-first-product-detail', async ({ page }) => {
  await page.goto('/', { waitUntil: 'domcontentloaded' });

  const firstProduct = page.locator('a[href*="/product"]').first();
  await expect(firstProduct).toBeVisible();

  await firstProduct.click();

  await expect(page).toHaveURL(/\/product/);
  await expect(page.locator('body')).toContainText(/Add To Cart|Add to Cart|cart/i);
});

test('catalog-product-detail-has-price', async ({ page }) => {
  await page.goto('/', { waitUntil: 'domcontentloaded' });

  await page.locator('a[href*="/product"]').first().click();

  await expect(page.locator('body')).toContainText(/\$/);
});

