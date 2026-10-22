# The program

All of this is in `lib/domain/plan.dart` (pure Dart) and is explained to the user in `lib/ui/features/settings/views/guide_page.dart`. The aim is the fastest loss that keeps most of it as fat, with as few things to track as possible. Calories and protein do most of the work; steps, lifting and sleep protect muscle and make the deficit easier to keep.

## Data collected

| When | What | Why |
|---|---|---|
| Onboarding | Sex, birthday, height, weight, goal weight, waist (optional), activity level, strength-training experience, pace, safety screen (pregnancy/breastfeeding, eating-disorder history, diabetes medicine, GLP-1, kidney disease), diet style, Apple Health or Health Connect permission | Starting maintenance (Mifflin-St Jeor × activity), protein target, safety rules, advice wording |
| Daily | Food (the core input), morning weigh-in, "food log complete" flag; optional hunger, energy, water. From Health: steps, active and resting energy, sleep, resting HR, workouts, smart-scale weights | Adaptive maintenance needs intake and weight; the complete flag keeps partial days out of the estimate |
| Weekly | Waist, average hunger and energy, adherence, whether to take a maintenance week. The app adds a review of the trend, logging, protein, steps, lifting and sleep | Updates maintenance; feedback on the habits that matter |

## Maintenance (TDEE)

The starting estimate (`startingTDEE`) is the Mifflin-St Jeor BMR × activity factor (1.2, 1.375, 1.55 or 1.725). If the watch has supplied at least a week of total burn (resting + active), the estimate is the average of the formula and 0.9 × the watch figure. Wrist devices tend to overestimate.

The adaptive estimate (`adaptiveTDEE`) uses the same idea as MacroFactor and The Hacker's Diet. Energy balance says *intake − expenditure = change in stores*, so

```
observed maintenance = average intake − (weight slope in kg/day × 7,700 kcal/kg)
```

The window is the 21 days ending yesterday, never including the plan's first week (water and glycogen losses there would make maintenance look far too high). It needs a span of at least 14 days, at least 10 counted intake days and at least 6 weigh-ins.

The slope is a least-squares line through the raw weigh-ins, not the smoothed trend. The EMA trend lags behind a steady loss, so its slope over a short window understates the loss and the estimate runs low. A straight-line fit has no lag, and with 6 or more points the day-to-day water noise largely cancels.

A day counts if it's marked complete, or if it isn't marked and has at least 1,000 kcal logged. A day marked incomplete never counts. Days that don't count are left out instead of being treated as low intake.

The observed value is clamped to between 1.0 and 2.5 × BMR. The estimate then moves `0.5 × coverage` of the way from the old value to the observed one, where coverage is counted days ÷ window days. One odd week can't swing it, and patchy logging moves it less.

## Targets (`targets`)

| Target | Rule | Reason / source |
|---|---|---|
| Deficit | pace × body weight × 7,700 / 7 per day, where pace is 0.5 %, 0.75 % (default) or 1 % of body weight a week; capped at 25 % of maintenance (30 % for the fastest pace) | 0.5 to 1 %/week keeps most loss as fat with protein and lifting (Garthe 2011, Helms 2014). The cap stops very large deficits for heavier people |
| Calorie floor | 1,500 kcal (male) / 1,200 kcal (female) | Common minimums without medical supervision |
| Rounding | Calories to the nearest 10 | |
| Protein | 1.6 g/kg of goal weight, at most 40 % of calories | Muscle gain from resistance training stops increasing above about 1.6 g/kg (Morton 2018); during weight loss, intakes over 1.3 g/kg help keep muscle (Kokura 2024); goal weight keeps it sensible for larger bodies |
| Fat | max(30 % of calories, 0.6 g/kg goal weight) | Hormones, absorbing fat-soluble vitamins |
| Carbs | The rest | Split matters far less than calories and protein |
| Fibre | max(25 g, 14 g per 1,000 kcal) | Dietary Guidelines for Americans; most filling thing to add |
| Steps | 14-day average + 1,000, rounded to 500, kept within 7,000 to 10,000 (8,000 with no data) | The drop in mortality levels off at 6,000 to 8,000 steps a day for adults 60 and over and 8,000 to 10,000 for younger adults (Paluch 2022) |
| Maintenance | No deficit when the trend is within 0.3 kg of goal, during a maintenance break, or when the safety screen says stop | |

The exercise bonus (`AppRepository.calorieTarget`, off by default) adds half of the day's active energy above the 14-day average. It's off because maintenance already includes normal activity and watches overestimate burns.

After 12 or more weeks in a deficit, the check-in suggests 1 or 2 weeks at maintenance (MATADOR, Byrne 2018).

## Trend weight

An exponential moving average with 10 % smoothing per day (The Hacker's Diet), applied once per elapsed day so gaps are handled: `alpha = 1 − 0.9^days`. Progress, rate and time-to-goal on the Trends tab come from the trend, never from single weigh-ins.

## Safety (`warnings`, `AppRepository.trendAlerts`)

Being under 18, pregnant or breastfeeding, or under a BMI of 18.5 stops the deficit: targets go to maintenance.

The app shows a caution for a goal BMI under 18.5, a history of eating disorders (involve a clinician), diabetes medicines that can cause lows, and kidney disease (ask before high protein). GLP-1 medicines get an info note: in STEP 1's body-composition substudy, more than a third of the weight lost was lean mass (15.0 % of body weight lost, 9.7 % of a lean mass that made up about 54 % of the body), so protein and lifting matter more.

Trend alerts fire when the trend drops more than 1.5 % a week over two weeks (after the first 3 weeks), or when intake averages more than 100 kcal under the floor over 4 or more counted days.

## Weekly feedback (`feedback`)

Comments, in order: fewer than 5 logged days; losing faster than 1.5 %/week, slower than 40 % of the planned pace, or on track; protein under 85 % of target; fewer than 2 lifting sessions; steps under 85 % of the goal; sleep under 7 h; 12+ weeks in a deficit.

## Sources

- Mifflin et al., Am J Clin Nutr 1990; Frankenfield et al., J Am Diet Assoc 2005 (BMR equations)
- Hall et al., Lancet 2011 (dynamic energy balance; why "3,500 kcal per pound" overpromises)
- Garthe et al., IJSNEM 2011; Helms et al., JISSN 2014 (rate of loss and lean mass)
- Morton et al., Br J Sports Med 2018; Longland et al., Am J Clin Nutr 2016; Jäger et al., J Int Soc Sports Nutr 2017; Kokura et al., Clin Nutr ESPEN 2024 (protein)
- Dietary Guidelines for Americans 2020 to 2025 (fibre, fat)
- Physical Activity Guidelines for Americans, 2nd ed., 2018; Paluch et al., Lancet Public Health 2022 (steps)
- Cava et al., Adv Nutr 2017 (preserving muscle during weight loss)
- Nedeltcheva et al., Ann Intern Med 2010 (sleep and lean-mass loss)
- Walker, *The Hacker's Diet*; Burke et al., J Am Diet Assoc 2011; Steinberg et al., Obesity 2013 (self-monitoring and daily weighing)
- Byrne et al., Int J Obes 2018 (MATADOR, intermittent dieting)
- NICE guideline NG246, Overweight and obesity management, 2025 (waist-to-height under 0.5)
- Jensen et al., AHA/ACC/TOS obesity guideline 2013; Wilding et al., NEJM 2021 (STEP 1), and Wilding et al., J Endocr Soc 2021 (STEP 1 body composition)
