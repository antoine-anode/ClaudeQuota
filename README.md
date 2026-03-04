<p align="center">
  <img src="packaging/AppIcon_1024.png" width="128" alt="ClaudeQuota icon">
</p>

<h1 align="center">ClaudeQuota</h1>

<p align="center">
  <b>Ton quota Claude, en un coup d'œil.</b><br>
  App macOS native qui affiche l'utilisation de ton quota Claude (plan Max) directement dans la barre de menu.
</p>

<p align="center">
  <a href="https://github.com/antoine-anode/ClaudeQuota/releases/latest"><img src="https://img.shields.io/github/v/release/antoine-anode/ClaudeQuota?label=T%C3%A9l%C3%A9charger&color=E07850&style=for-the-badge" alt="Télécharger"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.9+-orange" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/macOS-13%2B-blue" alt="macOS 13+">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
  <img src="https://img.shields.io/github/downloads/antoine-anode/ClaudeQuota/total?color=E07850" alt="Downloads">
</p>

---

<p align="center">
  <code>36% 3h12m</code> &nbsp; usage normal &nbsp;&nbsp;·&nbsp;&nbsp;
  <code>🔴 82% 0h54m</code> &nbsp; rouge si ≥ 80 % &nbsp;&nbsp;·&nbsp;&nbsp;
  <code>🔵 36% 8m</code> &nbsp; bleu si reset < 15 min
</p>

---

## Fonctionnalités

- **Pourcentage d'usage** de la fenêtre glissante de 5 h, en temps réel
- **Temps avant reset** basé sur le timestamp serveur (pas une estimation)
- **Couleurs adaptatives** : rouge si usage ≥ 80 %, bleu si reset dans ≤ 15 min
- **Affichage compact** : `36% 3h12m` ou `36% 8m` (heures masquées quand = 0)
- **Refresh adaptatif** : toutes les 2 min (toutes les 30 s au‑dessus de 75 %)
- **Réveil intelligent** : refresh automatique après mise en veille (délai réseau de 3 s)
- **Menu déroulant** : usage 7 j, status, fallback, ancienneté des données
- **Lancement au démarrage** via LaunchAgent macOS
- **Zéro config** : réutilise le token OAuth de Claude Code
- **Coût nul** : probe API minimale avec Haiku (1 token)

## Installation

### Télécharger le DMG (recommandé)

1. **[Télécharger ClaudeQuota.dmg](https://github.com/antoine-anode/ClaudeQuota/releases/latest)**
2. Ouvrir le DMG, glisser **ClaudeQuota.app** dans **Applications**
3. Lancer l'app

> **Gatekeeper** : l'app n'est pas signée Apple. Au premier lancement, clic droit → Ouvrir, ou :
> ```bash
> xattr -d com.apple.quarantine /Applications/ClaudeQuota.app
> ```

### Build depuis les sources

```bash
git clone https://github.com/antoine-anode/ClaudeQuota.git && cd ClaudeQuota
make install    # Build + /Applications + lancement au démarrage
```

## Prérequis

- macOS 13+ (Ventura ou supérieur)
- **Claude Code installé et connecté** — le token OAuth est lu depuis le Keychain

## Comment ça marche

```
┌──────────────┐      POST /v1/messages       ┌──────────────────┐
│              │  ─────────────────────────>   │                  │
│  ClaudeQuota │   (Haiku, 1 token, ~0 coût)  │   Anthropic API  │
│              │  <─────────────────────────   │                  │
└──────┬───────┘      response headers         └──────────────────┘
       │
       │  anthropic-ratelimit-unified-5h-utilization: 0.36
       │  anthropic-ratelimit-unified-5h-reset: 1771506000
       │  anthropic-ratelimit-unified-7d-utilization: 0.26
       │  anthropic-ratelimit-unified-status: allowed
       │
       ▼
  ┌──────────┐
  │ 36% 3h12m│  ← barre de menu macOS
  └──────────┘
```

L'app lit le **token OAuth de Claude Code** depuis le Keychain, envoie une requête minimale à l'API Anthropic, et parse les **headers de rate limit** de la réponse. Le temps affiché provient du timestamp serveur — c'est le moment exact où le quota sera réinitialisé.

## Menu déroulant

| Élément                 | Description                              |
|-------------------------|------------------------------------------|
| Usage 5 h : 36 %       | Utilisation de la fenêtre glissante 5 h  |
| Usage 7 j : 26 %       | Utilisation de la fenêtre glissante 7 j  |
| Status : allowed        | Status du rate limit                     |
| Fallback disponible     | Si un modèle fallback est dispo          |
| Mis à jour il y a X s  | Ancienneté de la dernière mesure         |
| Rafraîchir              | Force un refresh immédiat                |
| Voir les logs           | Ouvre le fichier de log                  |
| Lancer au démarrage     | Toggle le LaunchAgent                    |
| Quitter                 | Ferme l'app                              |

## Commandes Make

| Commande         | Description                                 |
|------------------|---------------------------------------------|
| `make build`     | Compile en release                          |
| `make bundle`    | Crée le .app bundle                         |
| `make dmg`       | Crée le DMG avec drag‑and‑drop              |
| `make install`   | Installe dans /Applications + LaunchAgent   |
| `make uninstall` | Supprime tout                               |
| `make clean`     | Nettoie les fichiers de build               |

## Structure du projet

```
ClaudeQuota/
├── Package.swift                    # SwiftPM manifest
├── Makefile                         # Build, bundle, DMG, install
├── packaging/
│   ├── Info.plist                   # App bundle metadata
│   ├── AppIcon.icns                 # Icône macOS
│   └── AppIcon_1024.png             # Preview
└── Sources/ClaudeQuota/
    ├── main.swift                   # Point d'entrée NSApplication
    ├── AppDelegate.swift            # Menu bar UI, timer, refresh
    └── QuotaService.swift           # Keychain, API probe, parsing
```

## Dépannage

**`err` dans la barre de menu** — Vérifie que Claude Code est connecté :
```bash
claude auth status
```

**`--` qui ne change pas** — L'app attend la réponse API. Vérifie ta connexion et les logs :
```bash
cat /tmp/claude-quota.log
```

**Popup Keychain** — Clique **Toujours autoriser**. Si tu build depuis les sources, un certificat de signature stable est recommandé (voir Makefile).

## Désinstallation

```bash
make uninstall
```

## Licence

MIT
