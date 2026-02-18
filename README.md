# ☁ Claude Quota Monitor

App macOS native qui affiche l'utilisation de ton quota Claude (plan Max) directement dans la barre de menu.

![Swift](https://img.shields.io/badge/Swift-5.9+-orange) ![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![License](https://img.shields.io/badge/license-MIT-green)

```
☁ 36% | 3h12m       usage normal
☁ 82% | 0h54m       texte rouge (≥80%)
```

---

## Fonctionnalites

- **Pourcentage d'usage** de la fenetre glissante de 5h
- **Temps estime** avant recuperation du quota
- **Texte rouge** quand l'usage depasse 80%
- **Refresh adaptatif** : toutes les 2 min (toutes les 30s au-dessus de 75%)
- **Menu deroulant** avec details (usage 7j, status, fallback)
- **Lancement au demarrage** via LaunchAgent macOS
- **Zero config** : reutilise le token OAuth de Claude Code

## Prerequis

- macOS 13+ (Ventura ou superieur)
- Swift 5.9+ (`xcode-select --install` si besoin)
- **Claude Code installe et connecte** (le token OAuth est lu depuis le Keychain)

## Installation

### Build depuis les sources

```bash
git clone <repo-url> && cd ClaudeQuota

# Build release
swift build -c release

# Copier le binaire
cp .build/release/ClaudeQuota /usr/local/bin/claude-quota
```

### Lancer

```bash
claude-quota
```

L'icone `☁` apparait dans la barre de menu. Aucune fenetre, aucune icone dans le Dock.

### Lancement automatique au demarrage

**Option 1 : Depuis le menu de l'app**

Clic sur `☁` dans la barre de menu > **Lancer au demarrage**

**Option 2 : Manuellement**

```bash
# Creer le LaunchAgent
cat > ~/Library/LaunchAgents/com.claude.quota.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.quota</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/claude-quota</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/tmp/claude-quota.log</string>
</dict>
</plist>
EOF

# Charger
launchctl load ~/Library/LaunchAgents/com.claude.quota.plist
```

Pour desactiver :

```bash
launchctl unload ~/Library/LaunchAgents/com.claude.quota.plist
rm ~/Library/LaunchAgents/com.claude.quota.plist
```

## Comment ca marche

```
┌──────────────┐      probe request       ┌──────────────────┐
│              │  ──────────────────────>  │                  │
│  claude-     │   POST /v1/messages      │   Anthropic API  │
│  quota       │   (1 token, ~0 cout)     │                  │
│              │  <──────────────────────  │                  │
└──────┬───────┘   response headers       └──────────────────┘
       │
       │  anthropic-ratelimit-unified-5h-utilization: 0.36
       │  anthropic-ratelimit-unified-7d-utilization: 0.26
       │  anthropic-ratelimit-unified-status: allowed
       │
       ▼
  ┌──────────┐
  │ ☁ 36%    │  macOS Menu Bar
  │ | 3h12m  │
  └──────────┘
```

1. **Keychain** : Lit le token OAuth de Claude Code (`Claude Code-credentials`)
2. **API Probe** : Envoie une requete minimale (1 token) a l'API Anthropic avec le header `anthropic-beta: oauth-2025-04-20`
3. **Headers** : Parse les headers `anthropic-ratelimit-unified-*` de la reponse
4. **Affichage** : Met a jour la barre de menu avec le pourcentage et le temps estime

Le temps affiche est une **estimation** : il represente le quota restant dans la fenetre de 5h si tu arretes d'utiliser Claude maintenant.

## Menu deroulant

Clic sur l'icone `☁` pour voir :

| Element                | Description                              |
|------------------------|------------------------------------------|
| Usage 5h: 36%         | Pourcentage d'utilisation (fenetre 5h)   |
| Usage 7j: 26%         | Pourcentage d'utilisation (fenetre 7j)   |
| Status: allowed        | Status du rate limit                     |
| Fallback disponible    | Si un modele fallback est dispo          |
| Rafraichir             | Force un refresh immediat                |
| Lancer au demarrage    | Toggle le LaunchAgent                    |
| Quitter                | Ferme l'app                              |

## Structure du projet

```
ClaudeQuota/
├── Package.swift                    # SwiftPM manifest
├── README.md
└── Sources/ClaudeQuota/
    ├── main.swift                   # Point d'entree NSApplication
    ├── AppDelegate.swift            # Menu bar UI, timer, refresh
    └── QuotaService.swift           # Keychain + API + parsing headers
```

## Fichiers installes

| Fichier | Chemin |
|---------|--------|
| Binaire | `/usr/local/bin/claude-quota` |
| LaunchAgent | `~/Library/LaunchAgents/com.claude.quota.plist` |
| Logs | `/tmp/claude-quota.log` |

## Depannage

**`☁ err` dans la barre de menu**

Verifie que Claude Code est connecte :
```bash
claude auth status
```

Verifie les logs :
```bash
cat /tmp/claude-quota.log
```

**`☁ --` qui ne change pas**

L'app attend la reponse API. Verifie ta connexion internet et que le token est valide.

**Popup Keychain "claude-quota veut acceder au trousseau"**

Clic **Toujours autoriser** pour eviter que ca se reproduise.

## Desinstallation

```bash
# Arreter l'app
pkill claude-quota

# Supprimer le LaunchAgent
launchctl unload ~/Library/LaunchAgents/com.claude.quota.plist 2>/dev/null
rm ~/Library/LaunchAgents/com.claude.quota.plist

# Supprimer le binaire
rm /usr/local/bin/claude-quota
```

## License

MIT
