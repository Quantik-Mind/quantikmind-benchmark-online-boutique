# Expected Defect-Recall Matrix

> These results use expected oracle data. They are useful for pipeline validation only and must not be presented as validated defect-recall results.

| Method | Tests Executed | Execution Reduction | Defect Recall | Detected Scenarios | Missed Scenarios |
| --- | ---: | ---: | ---: | --- | --- |
| Traditional Approach (Full Suite) | 51 | 0.0% | 100.0% | OB-001 Checkout Regression, OB-002 Cart Regression, OB-003 Product Detail Regression, OB-004 Payment Regression | - |
| Random Approach | 11 | 78.4% | 50.0% | OB-002 Cart Regression, OB-003 Product Detail Regression | OB-001 Checkout Regression, OB-004 Payment Regression |
| History + Code Change Approach | 11 | 78.4% | 100.0% | OB-001 Checkout Regression, OB-002 Cart Regression, OB-003 Product Detail Regression, OB-004 Payment Regression | - |
| Quantik Mind | 11 | 78.4% | 75.0% | OB-001 Checkout Regression, OB-002 Cart Regression, OB-003 Product Detail Regression | OB-004 Payment Regression |
