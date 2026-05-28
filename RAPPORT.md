# RAPPORT — TP GitOps avec ArgoCD

## Binôme
- Valentin (valaack)

## Outillage (Étape 0)
- kubectl : v1.34.1
- helm : v3.17.3
- kind : v0.22.0
- argocd CLI : v2.12.6
- git : v2.43.0
- docker : v28.5.1
- yq : v4.49.2

## GitOps en 1 page (Étape 1)

### Push vs Pull

En TP1, la CI avait les droits sur le cluster et faisait kubectl apply à la fin du pipeline. Ça marche bien quand t'as un seul env et une seule équipe, mais dès que ça grossit c'est le bazar — personne sait ce qui tourne vraiment, les rollbacks sont galères, et donner un env perso à chaque dev c'est quasi impossible.

En TP2, ArgoCD tourne dans le cluster et lit Git toutes les 3 minutes. Toi tu commites, lui il applique. C'est lui qui a les droits, pas la CI. Le gros avantage : si quelqu'un touche au cluster à la main, ArgoCD s'en rend compte tout de suite.

### Tableau comparatif

| Question | Push (TP1) | Pull (ArgoCD) |
|---|---|---|
| Qui a les droits sur le cluster ? | GitHub Actions | ArgoCD uniquement |
| Historique des changements ? | Logs CI | git log sur platform/ |
| Modification manuelle du cluster ? | Drift silencieux | OutOfSync immédiat |
| Ajouter un environnement ? | Copier overlays + reconfigurer CI | Un fichier YAML dans platform/apps/ |
| Rollback ? | Relancer la CI sur l'ancien commit | git revert, ArgoCD fait le reste |
| 30 services ? | 30 pipelines avec droits cluster | 1 seul ArgoCD |
| Visibilité sur ce qui tourne ? | kubectl ou Freelens | UI ArgoCD, un coup d'oeil |

### Ma position
Je partirais sur du push pour un projet perso seul, c'est plus rapide à setup. Dès qu'on est plusieurs ou qu'on a plusieurs envs, GitOps s'impose — la démo de l'ApplicationSet avec les previews par PR m'a convaincu, c'est impossible à reproduire aussi simplement avec du push.

## Glossaire ArgoCD (Étape 2)

- **Application** : c'est la ressource ArgoCD qui fait le lien entre un repo Git et un namespace K8s. À ne pas confondre avec l'appli métier. Dans ce TP, notif-dev est une Application qui déploie le chart Helm de notif dans devhub-dev.
- **AppProject** : le garde-fou. Il définit quels repos et namespaces sont autorisés. Sans lui, n'importe quelle Application peut déployer n'importe où.
- **Source** : là où ArgoCD va chercher les manifests — un repo Git avec un chemin et une branche. Ici : services/notif/chart sur main.
- **Destination** : là où ArgoCD déploie — un cluster et un namespace. Ici : cluster local, namespace devhub-dev.
- **Sync** : ArgoCD applique l'état Git dans le cluster. Pas juste un kubectl apply — c'est tracé, auditable, et peut être automatique.
- **Prune** : si une ressource est dans le cluster mais plus dans Git, ArgoCD la supprime. Puissant mais dangereux si mal configuré.
- **App of Apps** : une Application qui pointe vers un dossier contenant d'autres Applications. La root dans ce TP crée notif-dev, annuaire-dev et planning-dev automatiquement.
- **ApplicationSet** : génère des Applications automatiquement à partir d'un générateur. Ici on s'en sert pour créer une preview par PR ouverte.
- **Sync wave** : permet de contrôler l'ordre d'application. Wave -1 passe avant wave 0. Utile pour s'assurer qu'un ConfigMap existe avant que le Deployment démarre.
- **Hook** : un job qui tourne à un moment précis du sync (avant, pendant, après). On l'a utilisé pour simuler une migration de BDD en PreSync.

## Bestiaire ArgoCD (Étape 8)

### 1. Drift + selfHeal
J'ai forcé le deployment à 5 replicas avec kubectl scale. ArgoCD a détecté l'écart avec Git (2 replicas) et est repassé à 2 tout seul grâce à selfHeal:true. Aucune intervention de ma part.

### 2. Tag image inexistant
J'ai commité un tag qui n'existe pas sur GHCR. ArgoCD a synced sans broncher — il applique ce qui est dans Git, pas ce qui est valide. Le pod est resté en ImagePullBackOff. Statut : Synced + Degraded. ArgoCD ne vérifie pas que l'image existe avant de déployer.

### 3. Rollback avec git revert
Après le commit foireux, j'ai fait git revert + push. ArgoCD a détecté le nouveau commit et re-syncé automatiquement. Service de nouveau Healthy en environ 3 minutes. Pas besoin de rejouer une pipeline, pas besoin de toucher au cluster.

### 4. Hook PreSync
J'ai ajouté un Job avec l'annotation argocd.argoproj.io/hook: PreSync. À chaque sync, le job tourne en premier et se supprime une fois terminé (HookSucceeded). Dans la vraie vie ça servirait pour une migration de base de données.

### 5. Sync waves
ConfigMap en wave -1, Deployment en wave 0. À chaque sync, le ConfigMap est créé en premier. Si on le rend invalide, le Deployment ne démarre pas — l'ordre est respecté.

### 6. Prune
Avec prune:true activé, j'ai supprimé le configmap.yaml du chart. Au sync suivant, ArgoCD a supprimé le ConfigMap du cluster. Ce n'est pas dans Git → ça n'existe pas dans le cluster.

## Sécurité ArgoCD (Étape 9)

### RBAC
Créé un utilisateur developer avec un rôle restreint : il peut voir et syncer uniquement notif-dev dans le projet devhub.

Test réel :
- argocd app sync annuaire-dev → PermissionDenied ✅
- argocd app sync notif-dev → Succeeded ✅

### Notifications
Configuré un trigger on-sync-failed qui poste sur webhook.site avec le nom de l'app, la révision et l'erreur en JSON.

### 3 métriques Prometheus
1. **argocd_app_info** — donne l'état de chaque Application (sync_status, health_status). En incident : permet de voir d'un coup combien d'apps sont cassées.
2. **argocd_app_sync_total** — compte les syncs par résultat (succès/échec). En incident : si le compteur d'échecs monte, une app a du mal à converger.
3. **argocd_git_request_duration_seconds** — temps de lecture du repo Git. En incident : si ça explose, le repo est lent ou inaccessible.

## Synthèse : ArgoCD et la prod (Étape 11)

### Ce que j'ai vraiment ressenti

| Opération | Ressenti |
|---|---|
| Déployer pour la première fois | Plus long à setup mais plus rassurant |
| Nouvelle version | Juste un commit, c'est agréable |
| Rollback | Nettement plus simple qu'au TP1 |
| Nouvel environnement | Bluffant — un fichier YAML et c'est plié |
| Preview par branche | La fonctionnalité qui m'a le plus impressionné |
| Détecter un drift | Automatique, pas besoin d'y penser |
| Hotfix à 3h du matin | Plus contraignant — obligé de passer par Git |

**2 opérations plus contraignantes :**
1. Le hotfix en urgence — devoir passer par une PR à 3h du matin c'est frustrant. Mais c'est voulu : ça force la traçabilité et évite les rustines oubliées.
2. Déboguer en live — on ne peut plus faire un kubectl edit rapide pour tester un truc. C'est contraignant mais ça évite les drifts silencieux qu'on a vus au TP1.

**L'opération qui justifie ArgoCD à elle seule :** les previews automatiques par PR. J'ai créé une branche, ouvert une PR, et en moins d'une minute un environnement complet était dispo dans ArgoCD. Fermer la PR le supprime proprement. C'est impossible à reproduire aussi simplement avec du push.

### Ce qu'ArgoCD ne fait pas

**1. Déploiement progressif**
En l'état, une nouvelle version touche 100% des pods d'un coup. En prod c'est risqué. Il faudrait ajouter Argo Rollouts pour faire du canary ou du blue/green.
→ https://argoproj.github.io/argo-rollouts/

**2. Validation des manifests**
ArgoCD applique ce qui est dans Git sans vérifier si c'est conforme aux règles de l'entreprise. Un :latest ou un container root passerait sans alerte. Il faudrait Kyverno pour bloquer ça.
→ https://kyverno.io/docs/

**3. Secrets dans Git**
On ne peut pas pousser des Secrets K8s en clair dans Git. Pour l'instant les secrets sont créés à la main avec kubectl. En prod il faudrait Sealed Secrets ou External Secrets Operator.
→ https://sealed-secrets.netlify.app/

**4. Signature des images**
Rien n'empêche de déployer une image non vérifiée. En prod il faudrait signer les images avec cosign et bloquer les images non signées via une admission policy.
→ https://docs.sigstore.dev/

**5. RBAC multi-équipe**
L'AppProject est une bonne base mais sans SSO/OIDC, la gestion des utilisateurs reste manuelle. Pour une vraie équipe il faudrait brancher GitHub OAuth ou un IdP.
→ https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/

**6. Disaster recovery**
Si le cluster explose, les PVC et les données des bases de données sont perdus. ArgoCD peut recréer les Deployments mais pas les données. Il faudrait Velero pour les snapshots.
→ https://velero.io/docs/

**7. Multi-cluster**
Tout est sur un seul cluster. En prod on voudrait au moins séparer staging et prod. ArgoCD supporte le multi-cluster via l'ApplicationSet cluster generator.
→ https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/

### Les 3 briques que j'ajouterais en priorité
1. **Sealed Secrets** — bloquer immédiatement, on ne peut pas travailler avec des secrets hors Git
2. **Argo Rollouts** — indispensable avant de mettre quoi que ce soit en prod
3. **Kyverno** — pour dormir tranquille et interdire les :latest et les containers root
