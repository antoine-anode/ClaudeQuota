# Claude Quota Monitor

App macOS native qui affiche l'utilisation de ton quota Claude (plan Max) directement dans la barre de menu.

![Swift](https://img.shields.io/badge/Swift-5.9+-orange) ![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![License](https://img.shields.io/badge/license-MIT-green)

```
☁ 36% | 3h12m       usage normal
☁ 82% | 0h54m       texte rouge (>=80%)
```

---

## Fonctionnalites

- **Pourcentage d'usage** de la fenetre glissante de 5h
- **Temps estime** avant recuperation du quota
- **Texte rouge** quand l'usage depasse 80%
- **Refresh adaptatif** : toutes les 2 min (toutes les 30s au-dessus de 75%)
- **Refresh automatique du token** OAuth quand il expire
- **Menu deroulant** avec details (usage 7j, status, fallback)
- **Lancement au demarrage** via LaunchAgent macOS
- **Zero config** : reutilise le token OAuth de Claude Code

## Prerequis

- macOS 13+ (Ventura ou superieur)
- **Claude Code installe et connecte** (le token OAuth est lu depuis le Keychain)
- Swift 5.9+ pour build depuis les sources (`xcode-select --install`)

## Installation

### Via DMG (recommande)

1. Telecharger le `.dmg` depuis [Releases](https://github.com/antoine-anode/ClaudeQuota/releases)
2. Ouvrir le DMG
3. Glisser **ClaudeQuota.app** dans **Applications**
4. Lancer l'app depuis Applications

> **Note Gatekeeper** : l'app n'est pas signee Apple. Au premier lancement, faire clic droit > Ouvrir, ou executer :
> ```bash
> xattr -d com.apple.quarantine /Applications/ClaudeQuota.app
> ```

### Build depuis les sources

```bash
git clone https://github.com/antoine-anode/ClaudeQuota.git && cd ClaudeQuota

# Build + installer dans /Applications + activer le lancement au demarrage
make install

# Ou juste creer le DMG
make dmg
```

### Commandes Make

| Commande | Description |
|----------|-------------|
| `make build` | Compile en release |
| `make bundle` | Cree le .app bundle |
| `make dmg` | Cree le DMG avec drag-and-drop |
| `make install` | Installe dans /Applications + LaunchAgent |
| `make uninstall` | Supprime tout |
| `make clean` | Nettoie les fichiers de build |

## Comment ca marche

```
┌──────────────┐      probe request       ┌──────────────────┐
│              │  ──────────────────────>  │                  │
│  ClaudeQuota │   POST /v1/messages      │   Anthropic API  │
│  .app        │   (1 token, ~0 cout)     │                  │
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
2. **Token Refresh** : Si le token a expire (401), le refresh automatiquement via OAuth
3. **API Probe** : Envoie une requete minimale (1 token) a l'API Anthropic
4. **Headers** : Parse les headers `anthropic-ratelimit-unified-*` de la reponse
5. **Affichage** : Met a jour la barre de menu avec le pourcentage et le temps estime

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
├── Makefile                         # Build, bundle, DMG, install
├── README.md
├── packaging/
│   └── Info.plist                   # App bundle metadata
└── Sources/ClaudeQuota/
    ├── main.swift                   # Point d'entree NSApplication
    ├── AppDelegate.swift            # Menu bar UI, timer, refresh
    └── QuotaService.swift           # Keychain, token refresh, API, headers
```

## Fichiers installes

| Fichier | Chemin |
|---------|--------|
| App | `/Applications/ClaudeQuota.app` |
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

**Popup Keychain "ClaudeQuota veut acceder au trousseau"**

Clic **Toujours autoriser** pour eviter que ca se reproduise.

## Desinstallation

```bash
make uninstall
```

Ou manuellement :

```bash
pkill ClaudeQuota
launchctl unload ~/Library/LaunchAgents/com.claude.quota.plist 2>/dev/null
rm ~/Library/LaunchAgents/com.claude.quota.plist
rm -rf /Applications/ClaudeQuota.app
```

## License

MIT
