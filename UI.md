Voici un prompt complet prêt à coller dans Claude Code :
Handoff — BPM Doctor : Redesign "Brutalist"
Contexte

Application Flutter de détection BPM via le microphone. Redesign complet de l'UI selon la direction Brutalist (option 1 validée en maquette).
Direction visuelle

Palette

    Background principal : #0a0a0a
    Texte primaire : #f0f0f0
    Accent / couleur active : #c01c28 (rouge berlinois)
    Texte secondaire / labels : #555555
    Séparateurs / tracks : #1a1a1a / #222222

Typographies

    Chiffre BPM + valeurs paramètres : Barlow Condensed, weight 900
    Labels, status, bouton : Space Mono, weight 700
    Casse : tout en majuscules, letterSpacing généreux (~0.3–0.4em)

Texture de fond

    Pattern de points 4×4px, opacité 3% blanc → BoxDecoration avec DecorationImage en repeat, ou shader custom

Structure de l'écran (de haut en bas)

SafeArea
├── Header (padding top 56px, horizontal 28px)
│   ├── "BPM DOCTOR" — Space Mono 13px, letterSpacing 0.3em, couleur accent
│   └── Status "● REC" / "○ STOP" — Space Mono 11px, couleur accent si actif, #444 sinon
│
├── BPM Block (Expanded, centré verticalement, padding horizontal 28px)
│   ├── Label "BEATS PER MINUTE" — Space Mono 12px, #555, letterSpacing 0.4em
│   ├── Chiffre BPM — Barlow Condensed 184px, weight 900, lineHeight 0.85
│   │   └── Couleur : #f0f0f0 au repos → #c01c28 pendant 150ms à chaque nouveau BPM (pulse)
│   ├── "BPM" — Space Mono 18px, #444, letterSpacing 0.3em
│   └── Barre de progression linéaire
│       ├── Track : #1a1a1a, height 3px
│       └── Fill : #c01c28, width proportionnelle à (bpm - 60) / 120, transition 300ms
│
├── Paramètres (padding horizontal 28px, gap 20px)
│   ├── Fenêtre (en secondes, range 1–10, step 0.5)
│   │   ├── Row : label "FENÊTRE" (Space Mono 11px #555) + valeur "{x}s" (Barlow Condensed 20px 900 #f0f0f0)
│   │   └── Slider custom : track #222 2px, thumb diamant rouge #c01c28 16×16px
│   └── Seuil (entier, range 0–100)
│       ├── Row : label "SEUIL" + valeur "{x}"
│       └── Slider identique
│
└── Bouton (padding horizontal 28px, bottom 44px)
    └── Bouton pleine largeur, height 64px
        ├── État repos : border 2px #c01c28, background transparent, texte #c01c28
        │   "▶ ÉCOUTER" — Space Mono 15px, letterSpacing 0.4em
        └── État actif (recording) : background #c01c28, texte #0a0a0a
            "■ STOP"

Comportements & animations
Événement 	Animation
Nouveau BPM détecté 	Chiffre flash vers #c01c28 pendant 150ms puis retour #f0f0f0
Barre de progression 	Transition width en 300ms, easing Curves.easeOutExpo
Bouton hover (desktop) / press (mobile) 	Remplissage fond de gauche à droite en 200ms
Démarrage écoute 	Status passe à "● REC", glow rouge sur accent

Affichage BPM inactif : afficher "---" (trois tirets) quand pas d'écoute en cours.
Composants Flutter suggérés

    AnimatedDefaultTextStyle ou TweenAnimationBuilder pour le pulse BPM
    SliderTheme avec SliderThemeData custom (thumb losange via CustomPainter)
    LinearProgressIndicator custom ou AnimatedContainer pour la barre
    Stack + Positioned pour le pattern de fond
    GoogleFonts.barlowCondensed() + GoogleFonts.spaceMono() via le package google_fonts

Ce qu'il ne faut PAS faire

    Pas de Card avec elevation ou ombres
    Pas de rounded corners (tout est angulaire)
    Pas de couleurs Material par défaut (override complet du thème)
    Pas de AppBar Flutter standard
