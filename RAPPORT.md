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

### Flux Push vs Pull

**Push (TP1)** : La CI (GitHub Actions) a les droits sur le cluster et exécute kubectl apply directement.
**Pull (TP2)** : Un agent (ArgoCD) dans le cluster lit Git en continu et fait converger l'état du cluster.

### Tableau comparatif

| Question | Push (kubectl apply en CI) | Pull (ArgoCD) |
|---|---|---|
| Qui a les droits sur le cluster ? | La CI / GitHub Actions | ArgoCD uniquement |
| Où est l'historique des changements ? | Logs CI + Git de l'app | Git du repo platform/ |
| Que se passe-t-il si un dev modifie le cluster à la main ? | Drift silencieux, personne ne le sait | ArgoCD détecte OutOfSync immédiatement |
| Comment ajouter un environnement de plus ? | Copier overlays, modifier CI, reconfigurer | Ajouter un fichier Application dans platform/apps/ |
| Comment faire un rollback ? | Relancer la CI sur l'ancien commit | git revert, ArgoCD re-converge automatiquement |
| Combien de pipelines pour 30 services ? | 30 pipelines avec droits cluster | 1 seul ArgoCD qui lit tous les repos |
| Qui voit en direct ce qui tourne ? | Personne sans accès cluster | Tout le monde via l'UI ArgoCD |

### Ma prise de position
Pour mes futurs projets perso, je commencerais par **push** car c'est plus simple à mettre en place rapidement. Je passerais en **pull (GitOps)** dès que l'équipe grandit ou que j'ai plusieurs environnements à gérer, car la traçabilité et les previews automatiques par branche justifient largement l'investissement.

## Glossaire ArgoCD (Étape 2)

- **Application** : ressource ArgoCD (pas l'app métier) qui lie un repo Git à un namespace Kubernetes. Ex: notif-dev pointe vers services/notif/chart et déploie dans devhub-dev.
- **AppProject** : brique de sécurité qui définit quels repos et namespaces sont autorisés. Ex: le projet devhub n'autorise que github.com/valaack/devhub-campus.
- **Source** : le repo Git + chemin + branche qu'ArgoCD lit. Ex: path: services/notif/chart, targetRevision: main.
- **Destination** : le cluster + namespace où ArgoCD déploie. Ex: server: https://kubernetes.default.svc, namespace: devhub-dev.
- **Sync** : ArgoCD applique l'état Git dans le cluster. Différent de kubectl apply car tracé, auditable, et déclenché par Git.
- **Prune** : ArgoCD supprime du cluster les ressources qui n'existent plus dans Git. Dangereux si mal configuré.
- **App of Apps** : une Application racine qui déploie d'autres Applications. Ex: root pointe vers platform/apps/dev/ et crée notif-dev, annuaire-dev, planning-dev.
- **ApplicationSet** : génère automatiquement des Applications à partir d'un générateur (branches, PRs). Ex: notif-preview génère une Application par PR ouverte.
- **Sync wave** : ordre d'application des ressources. Wave -1 avant wave 0. Ex: ConfigMap (wave -1) avant Deployment (wave 0).
- **Hook** : job qui s'exécute à un moment précis du sync. Ex: PreSync pour une migration de base de données avant le déploiement.

## Bestiaire ArgoCD (Étape 8)

### 1. Drift + selfHeal
- Action : kubectl scale deploy notif-dev-notif --replicas=5
- Observation : ArgoCD passe en OutOfSync puis selfHeal remet automatiquement à 2 replicas
- Conclusion : selfHeal:true corrige les modifications manuelles sans intervention humaine

### 2. Tag image inexistant
- Action : commit avec image.tag: "tagquiexistepas"
- Observation : Synced + Degraded, pod en ImagePullBackOff
- Conclusion : ArgoCD applique l'état Git même si l'image n'existe pas. Il ne vérifie pas l'existence de l'image.

### 3. Rollback avec git revert
- Action : git revert HEAD + git push
- Observation : ArgoCD détecte le nouveau commit, re-sync, service redevient Healthy en ~3 minutes
- Conclusion : le rollback est simple, tracé dans Git, sans rejouer une pipeline

### 4. Hook PreSync
- Action : ajout d'un job avec annotation argocd.argoproj.io/hook: PreSync
- Observation : le job s'exécute et se termine avant le déploiement, puis se supprime (HookSucceeded)
- Conclusion : utile pour les migrations de base de données avant un déploiement

### 5. Sync waves
- Action : ConfigMap wave -1, Deployment wave 0
- Observation : le ConfigMap est appliqué avant le Deployment à chaque sync
- Conclusion : permet de contrôler l'ordre d'application des ressources

### 6. Prune
- Action : prune:true + suppression de configmap.yaml dans Git
- Observation : le ConfigMap disparaît du cluster au prochain sync
- Conclusion : prune:true nettoie proprement les ressources supprimées de Git. Dangereux si activé trop tôt.

## Sécurité ArgoCD (Étape 9)

### RBAC
- Rôle developer : peut voir et syncer uniquement notif-dev dans le projet devhub
- Rôle platform-admin : tous les droits
- Test : argocd app sync annuaire-dev depuis le compte developer → PermissionDenied ✅
- Test : argocd app sync notif-dev depuis le compte developer → Succeeded ✅

### Notifications
- Trigger on-sync-failed configuré vers webhook.site
- Payload JSON contenant : nom de l'application, révision, erreur

### 3 métriques Prometheus utiles
1. argocd_app_info : état de chaque Application (sync_status, health_status). Utile pour détecter les apps OutOfSync ou Degraded.
2. argocd_app_sync_total : nombre de syncs par application et résultat. Utile pour détecter les échecs répétés.
3. argocd_git_request_duration_seconds : temps de lecture du repo Git. Utile pour détecter un repo Git lent ou inaccessible.

## Synthèse : ArgoCD et la prod (Étape 11)

### Rétrospective TP1 → TP2

| Opération | Ressenti avec ArgoCD |
|---|---|
| Déployer pour la première fois | Plus rassurant — tout est dans Git |
| Déployer une nouvelle version | Plus rapide — juste un commit |
| Rollback | Beaucoup plus simple — git revert |
| Ouvrir un environnement de plus | Impressionnant — juste un fichier YAML |
| Preview par branche | Magique — ApplicationSet fait tout |
| Détecter un drift | Automatique — OutOfSync immédiat |
| Hotfix en urgence | Plus contraint — doit passer par Git |

**2 opérations plus contraignantes avec ArgoCD :**
1. Hotfix en urgence : on ne peut plus faire kubectl edit directement, tout doit passer par Git. La contrainte est justifiée car ça force la traçabilité.
2. Déboguer un problème en live : on ne peut plus modifier une ressource à la main pour tester. Justifié car ça évite les drifts silencieux.

**L'opération qui justifie ArgoCD à elle seule :** les previews automatiques par branche via ApplicationSet. Impossible à faire simplement sans GitOps.

### Ce qu'ArgoCD ne sait pas faire

**1. Déploiement progressif (canary, blue/green)**
- Risque : en prod, un bug déploié d'un coup touche 100% des utilisateurs
- Outil : Argo Rollouts ou Flagger
- Référence : https://argoproj.github.io/argo-rollouts/

**2. Validation des manifests avant sync**
- Risque : un manifest invalide ou non conforme aux policies est déployé sans alerte
- Outil : Kyverno ou OPA Gatekeeper
- Référence : https://kyverno.io/docs/

**3. Gestion des secrets dans Git**
- Risque : pousser un Secret Kubernetes en clair dans Git expose les credentials
- Outil : Sealed Secrets ou External Secrets Operator
- Référence : https://sealed-secrets.netlify.app/

**4. Signature et provenance des images**
- Risque : une image non signée peut être remplacée par une image malveillante
- Outil : cosign + Sigstore
- Référence : https://docs.sigstore.dev/

**5. RBAC multi-équipe**
- Risque : sans AppProject bien configuré, une équipe peut déployer dans le namespace d'une autre
- Outil : AppProject + SSO/OIDC
- Référence : https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/

**6. Disaster recovery applicatif**
- Risque : perte des données en cas de crash cluster (PVC, bases de données)
- Outil : Velero + snapshots PVC
- Référence : https://velero.io/docs/

**7. Multi-cluster**
- Risque : avec un seul cluster, pas de séparation prod/staging, pas de résilience
- Outil : ApplicationSet cluster generator
- Référence : https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/

### Les 3 briques prioritaires après ArgoCD
1. **Sealed Secrets** — pour pouvoir pousser des secrets dans Git sans risque
2. **Argo Rollouts** — pour des déploiements progressifs en prod
3. **Kyverno** — pour valider les manifests et interdire les :latest
