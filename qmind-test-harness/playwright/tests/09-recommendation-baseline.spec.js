const { test, expect } = require('@playwright/test');

// Opens the first product detail page from the homepage.
// Returns the href so callers can confirm a real /product/ URL was navigated.
async function openFirstProductDetail(page) {
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  const firstLink = page.locator('a[href*="/product/"]').first();
  await expect(firstLink).toBeVisible();
  const href = await firstLink.getAttribute('href');
  await firstLink.click();
  await expect(page).toHaveURL(/\/product\//);
  return href;
}

// Asserts that the product detail page core content is intact:
// product name area, price, and Add To Cart button must all be present.
async function assertProductDetailLoaded(page) {
  await expect(page.locator('h2').first()).toBeVisible();
  await expect(page.locator('.product-price')).toBeVisible();
  await expect(page.getByRole('button', { name: /add to cart/i })).toBeVisible();
}

test('recommendation-section-visible-on-detail', async ({ page }) => {
  // Navigate: homepage -> first product detail link
  await openFirstProductDetail(page);

  // Core product detail must still be present (not just a blank or error page)
  await assertProductDetailLoaded(page);

  // Recommendation section must be present and visible.
  // Selector: section.recommendations (rendered by templates/recommendations.html)
  // Heading:  h2 "You May Also Like" inside that section
  const recSection = page.locator('section.recommendations');
  await expect(recSection).toBeVisible();
  await expect(recSection.locator('h2')).toContainText('You May Also Like');
});
