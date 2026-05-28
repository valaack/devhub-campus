# Squelette à compléter — étape 3 du TP.
# Contraintes (non négociables, lisez le polycopié) :
#   - multi-stage,
#   - image finale ≤ 200 Mo,
#   - utilisateur non-root,
#   - pas de secret en ENV/ARG,
#   - LABEL org.opencontainers.image.source pointant vers le dépôt Git.

# ---- Stage 1 : build / install des dépendances ----
# TODO : choisissez une image de base reproductible (pin par digest ou par tag immuable).
FROM node:20-alpine AS build

WORKDIR /app

# TODO : copiez le package.json puis lancez `npm ci` AVANT de copier le code.
# Indice : ça optimise le cache Docker.

# TODO : copiez le reste du code source.

# ---- Stage 2 : image runtime ----
# TODO : repartez d'une image runtime minimale (Alpine, Distroless, etc.).
FROM node:20-alpine AS runtime

# TODO : ajoutez le LABEL org.opencontainers.image.source.

WORKDIR /app

# TODO : copiez depuis le stage `build` uniquement ce qui est nécessaire au runtime
# (node_modules et src/), pas plus.

# TODO : créez un utilisateur non-root et passez en USER. NE PAS rester en root.

ENV PORT=8080 \
    LOG_LEVEL=info \
    NODE_ENV=production

EXPOSE 8080

# TODO : configurez la commande de démarrage.
# CMD ["node", "src/index.js"]
