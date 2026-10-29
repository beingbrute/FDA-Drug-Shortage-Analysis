# Hypothesis test: pediatric drugs and full unavailability

Run on 29 October 2026 against the `fda_shortages` database (FDA list downloaded 26 October 2026),
as `analyst_user` through the `v_drug_summary` view.

**Question:** among drugs in current shortage, are pediatric drugs more likely than other drugs
to have at least one product that is fully unavailable?

- **Null hypothesis:** the share of drugs with an unavailable product is the same in both groups.
- **Alternative:** the shares differ (two-sided).
- **Unit:** the drug (69 drugs). Product records of the same drug are not independent.
- **Test:** Fisher's exact test, significance level 0.05. One group has very few drugs
  without an unavailable product, so a chi-square test would be unreliable.

## Result

| group     |   At least one unavailable |   None unavailable |   Drugs | Share with unavailable   |
|:----------|---------------------------:|-------------------:|--------:|:-------------------------|
| Pediatric |                         16 |                  1 |      17 | 94%                      |
| Other     |                         42 |                 10 |      52 | 81%                      |

Odds ratio = 3.81, p-value = 0.270.

**p = 0.270 is above 0.05: there is no statistically significant difference. The data does not show that pediatric drugs are more likely to be fully unavailable.**

## Limits

- The FDA list is not a random sample of drugs, so the result describes this list, not all drugs.
- With 69 drugs the test can detect only large differences; a real but small difference could be missed.
- "Pediatric" means the FDA lists Pediatric among the drug's therapeutic areas in at least one current record.
