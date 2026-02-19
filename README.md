<p align="center">
  <img src="packaging/AppIcon_1024.png" width="128" alt="ClaudeQuota icon">
</p>

<h1 align="center">Claude Quota Monitor</h1>

<p align="center">
  App macOS native qui affiche l'utilisation de ton quota Claude (plan Max) directement dans la barre de menu.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.9+-orange" alt="Swift">
  <img src="https://img.shields.io/badge/macOS-13%2B-blue" alt="macOS">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

<p align="center">
  <code>36% 3h12m</code> &nbsp; usage normal &nbsp;&nbsp;|&nbsp;&nbsp;
  <code style="color:red">82% 0h54m</code> &nbsp; rouge >=80% &nbsp;&nbsp;|&nbsp;&nbsp;
  <code style="color:blue">36% 8m</code> &nbsp; bleu <= 15min avant reset
</p>

---

## Fonctionnalites

- **Pourcentage d'usage** de la fenetre glissante de 5h
- **Temps avant reset** fourni par le serveur (timestamp reel, pas une estimation)
- **Couleurs dissociees** : rouge si usage >= 80%, bleu si reset dans <= 15min
- **Affichage compact** : `36% 3h12m` ou `36% 8m` (heures masquees quand = 0)
- **Refresh adaptatif** : toutes les 2 min (toutes les 30s au-dessus de 75%)
- **Refresh automatique du token** OAuth quand il expire
- **Refresh au reveil** apres mise en veille (avec delai de 3s pour le reseau)
- **Menu deroulant** avec details (usage 7j, status, fallback, anciennete des donnees)
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
       │  anthropic-ratelimit-unified-5h-reset: 1771506000
       │  anthropic-ratelimit-unified-7d-utilization: 0.26
       │  anthropic-ratelimit-unified-status: allowed
       │
       ▼
  ┌──────────┐
  │ 36%      │  macOS Menu Bar
  │ 3h12m    │
  └──────────┘
```

1. **Keychain** : Lit le token OAuth de Claude Code (`Claude Code-credentials`)
2. **Token Refresh** : Si le token a expire (401), le refresh automatiquement via OAuth
3. **API Probe** : Envoie une requete minimale (1 token) a l'API Anthropic
4. **Headers** : Parse les headers `anthropic-ratelimit-unified-*` de la reponse
5. **Affichage** : Met a jour la barre de menu avec le pourcentage et le temps reel de reset

Le temps affiche provient du **timestamp serveur** (`5h-reset`), c'est le moment exact ou le quota sera reinitialise.

## Menu deroulant

Clic sur le texte dans la barre de menu :

| Element                | Description                              |
|------------------------|------------------------------------------|
| Usage 5h: 36%         | Pourcentage d'utilisation (fenetre 5h)   |
| Usage 7j: 26%         | Pourcentage d'utilisation (fenetre 7j)   |
| Status: allowed        | Status du rate limit                     |
| Fallback disponible    | Si un modele fallback est dispo          |
| Mis a jour il y a Xs   | Anciennete de la derniere mesure         |
| Rafraichir             | Force un refresh immediat                |
| Voir les logs          | Ouvre le fichier de log                  |
| Lancer au demarrage    | Toggle le LaunchAgent                    |
| Quitter                | Ferme l'app                              |

## Structure du projet

```
ClaudeQuota/
├── Package.swift                    # SwiftPM manifest
├── Makefile                         # Build, bundle, DMG, install
├── README.md
├── packaging/
│   ├── Info.plist                   # App bundle metadata
│   ├── AppIcon.icns                 # Icone macOS (toutes tailles)
│   └── AppIcon_1024.png             # Preview de l'icone
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

**`err` dans la barre de menu**

Verifie que Claude Code est connecte :
```bash
claude auth status
```

Verifie les logs :
```bash
cat /tmp/claude-quota.log
```

**`--` qui ne change pas**

L'app attend la reponse API. Verifie ta connexion internet et que le token est valide.

**Popup Keychain "ClaudeQuota veut acceder au trousseau"**

Clic **Toujours autoriser** pour eviter que ca se reproduise. Si tu build depuis les sources, un certificat de signature stable est recommande (voir Makefile).

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
