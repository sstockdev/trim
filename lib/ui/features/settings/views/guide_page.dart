import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../domain/format.dart';
import '../../../../domain/models.dart';
import '../../../../domain/plan.dart';
import '../../../../data/repositories/app_repository.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';

/// What the program does and why, with sources.
class GuidePage extends StatelessWidget {
  const GuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<AppRepository>();
    final t = repository.targets;
    final p = repository.profile;
    final plant = p.diet == DietStyle.vegan || p.diet == DietStyle.vegetarian;
    return Scaffold(
      appBar: AppBar(title: const Text('How it works')),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          _topic(
            context,
            'Your calorie target',
            "Maintenance starts from the Mifflin-St Jeor equation times your activity level (averaged with your watch's reading when there's a week of it). After about three weeks the app works out your real maintenance from what you ate and how your weight trend moved, and updates it at each weekly check-in. The deficit comes from your chosen pace (0.5 to 1 % of body weight a week), is capped at 25 to 30 % of maintenance, and never takes you below ${Plan.calorieFloor(p.sex)} kcal.",
            [
              'Mifflin et al., Am J Clin Nutr 1990',
              'Frankenfield et al., J Am Diet Assoc 2005',
              "Hall et al., Lancet 2011 (why fixed '3,500 kcal per pound' rules overpromise)",
            ],
          ),
          _topic(
            context,
            'Protein: ${t.protein} g a day',
            '1.6 g per kg of goal weight. High protein during a deficit, together with lifting, protects muscle and keeps you fuller. Spread it over 3 or 4 meals of 25 to 40 g. ${plant ? 'Good plant sources: tofu, tempeh, seitan, lentils, Greek yogurt or soy yogurt, protein powder.' : 'Easy sources: chicken, fish, eggs, Greek yogurt, cottage cheese, lean beef, beans.'}',
            [
              'Morton et al., Br J Sports Med 2018',
              'Longland et al., Am J Clin Nutr 2016',
              'Jäger et al., ISSN position stand, 2017',
            ],
          ),
          _topic(
            context,
            'Fibre, fat and carbs',
            'Fibre: at least 14 g per 1,000 kcal; vegetables, fruit, beans and whole grains fill you up for few calories. Fat stays around 30 % of calories (not under 0.6 g/kg of goal weight). Carbs make up the rest. Within those, the split matters far less than total calories and protein.',
            ['Dietary Guidelines for Americans 2020 to 2025'],
          ),
          _topic(
            context,
            'Lifting and moving',
            "Strength-train 2 or 3 times a week, whole body, getting gradually stronger. ${p.strength == StrengthExperience.none ? 'As a beginner, start with 2 sessions of 6 to 8 exercises (squat or leg press, push-up or bench, row, hinge, overhead press, carry), 2 or 3 sets of 8 to 12 reps, stopping 1 to 3 reps before failure.' : 'Keep training hard; aim to hold or increase your strength while you lose.'} Walk every day: your step goal is ${Fmt.int_(t.steps)}, a bit above your current average. Aim for 150 to 300 minutes of moderate cardio a week in total.",
            [
              'Physical Activity Guidelines for Americans, 2nd ed., 2018',
              'Paluch et al., Lancet Public Health 2022 (steps and mortality)',
              'Cava et al., Adv Nutr 2017 (keeping muscle while losing weight)',
            ],
          ),
          _topic(
            context,
            'Sleep',
            '7 to 9 hours. In a controlled study, dieters sleeping 5.5 hours lost the same weight as those sleeping 8.5, but far more of it was muscle rather than fat, and they were hungrier.',
            ['Nedeltcheva et al., Ann Intern Med 2010'],
          ),
          _topic(
            context,
            'Weighing and the trend',
            'Weigh every morning after the bathroom, before eating. Day-to-day changes of 1 or 2 lb are water, salt and food in your gut. The trend line smooths these out; judge progress by it, week to week. Daily weighing plus food logging are the habits most consistently linked with successful loss.',
            ["Walker, The Hacker's Diet", 'Burke et al., J Am Diet Assoc 2011', 'Steinberg et al., Obesity 2013'],
          ),
          _topic(
            context,
            'Maintenance weeks',
            'Every 8 to 12 weeks, or whenever you need it, take 1 or 2 weeks at maintenance. In one trial, alternating two weeks of dieting with two weeks of maintenance gave more fat loss and better maintenance than dieting straight through.',
            ['Byrne et al., Int J Obes 2018 (MATADOR)'],
          ),
          _topic(
            context,
            'Waist',
            'Keep your waist under half your height. Waist-to-height ratio shows belly fat, which carries most of the health risk, and it can improve even when the scale stalls.',
            ['NICE guideline on overweight and obesity management'],
          ),
          _topic(
            context,
            'Safety',
            "The app won't set a deficit if you're under 18, pregnant or breastfeeding, or already underweight, and it flags losing more than 1.5 % a week or eating under the minimum. With diabetes medicines that can cause lows, a history of eating disorders, kidney disease or a GLP-1 medicine, involve your doctor. In a large trial of a GLP-1 medicine, more than a third of the weight lost was lean mass, so protein and lifting matter even more.",
            [
              'Jensen et al., AHA/ACC/TOS obesity guideline, 2013',
              'Wilding et al., NEJM 2021 and J Endocr Soc 2021 (STEP 1)',
            ],
          ),
        ],
      ),
    );
  }

  Widget _topic(BuildContext context, String title, String body, List<String> sources) => Section(
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 8),
          Text(body),
          const SizedBox(height: 8),
          Text(sources.join(' · '), style: TextStyle(fontSize: 11, color: context.secondaryText)),
        ],
      ),
    ],
  );
}
