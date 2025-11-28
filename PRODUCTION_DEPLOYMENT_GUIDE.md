# 🚀 Guide de Déploiement Production - Zugfahrt App

## 📋 Vue d'ensemble

Ce guide vous accompagne pour déployer **Zugfahrt App** en production avec une architecture complète incluant :

- **Application Spring Boot** sécurisée avec JWT
- **Base de données PostgreSQL** avec sauvegarde automatique
- **Cache Redis** pour les performances
- **Reverse Proxy Nginx** avec SSL et rate limiting
- **Monitoring** avec Prometheus et Grafana
- **Logs centralisés** et health checks

## 🏗️ Architecture Production

```
Internet
    ↓
[Nginx Reverse Proxy] ← SSL Termination, Rate Limiting
    ↓
[Spring Boot App] ← JWT Auth, API Business Logic
    ↓
[PostgreSQL DB] ← Données persistantes
[Redis Cache] ← Sessions, Cache
    ↓
[Prometheus + Grafana] ← Monitoring
```

## 📦 Pré-requis

### Système

- **Docker** >= 20.10
- **Docker Compose** >= 2.0
- **Minimum 4GB RAM**, 2 CPU cores
- **20GB stockage libre**

### Sécurité

- **Certificat SSL** (Let's Encrypt recommandé)
- **Variables d'environnement** sécurisées
- **Firewall** configuré
- **Sauvegarde** automatisée

## 🔧 Configuration Initiale

### 1. Cloner et configurer

```bash
git clone https://github.com/armel4/Zugfahrt.git
cd Zugfahrt-App
```

### 2. Configuration des variables d'environnement

```bash
# Copier le template
cp .env.example .env

# Éditer avec vos valeurs
nano .env
```

**Variables critiques à configurer :**

```bash
# Base de données
DB_PASSWORD=VotreSuperMotDePasseSecurise123!

# JWT (MINIMUM 32 caractères)
JWT_SECRET=VotreCleJWTTresSecuriseEtLongueDeAuMoins32Caracteres

# Redis
REDIS_PASSWORD=VotreMotDePasseRedisSecurise

# CORS (vos domaines)
CORS_ALLOWED_ORIGINS=https://votre-domaine.com,https://www.votre-domaine.com

# Email
SMTP_USERNAME=votre-email@gmail.com
SMTP_PASSWORD=votre-mot-de-passe-app

# Grafana
GRAFANA_PASSWORD=mot-de-passe-admin-grafana
```

### 3. Certificates SSL (Optionnel pour démarrage)

```bash
# Créer le dossier SSL
mkdir -p ssl

# Option 1: Let's Encrypt (recommandé)
certbot certonly --standalone -d votre-domaine.com -d www.votre-domaine.com
cp /etc/letsencrypt/live/votre-domaine.com/fullchain.pem ssl/cert.pem
cp /etc/letsencrypt/live/votre-domaine.com/privkey.pem ssl/key.pem

# Option 2: Certificat auto-signé (développement uniquement)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ssl/key.pem \
  -out ssl/cert.pem \
  -subj "/C=FR/ST=France/L=Paris/O=Zugfahrt/CN=votre-domaine.com"
```

## 🚀 Déploiement

### Déploiement Automatique (Recommandé)

**Windows PowerShell :**

```powershell
# Déploiement complet
.\deploy-prod.ps1 deploy

# Vérifier le statut
.\deploy-prod.ps1 status

# Voir les logs
.\deploy-prod.ps1 logs app
```

**Linux/macOS :**

```bash
# Rendre exécutable
chmod +x deploy-prod.sh

# Déploiement complet
./deploy-prod.sh deploy

# Vérifier le statut
./deploy-prod.sh status

# Voir les logs
./deploy-prod.sh logs app
```

### Déploiement Manuel

```bash
# 1. Construire les images
docker-compose -f docker-compose.prod.yml build

# 2. Démarrer les services de base
docker-compose -f docker-compose.prod.yml up -d db redis

# 3. Attendre que la DB soit prête
docker-compose -f docker-compose.prod.yml exec db pg_isready -U zugfahrt_user

# 4. Démarrer l'application
docker-compose -f docker-compose.prod.yml up -d app

# 5. Démarrer le proxy et monitoring
docker-compose -f docker-compose.prod.yml up -d nginx prometheus grafana
```

## 🔍 Vérification

### Health Checks

```bash
# Application
curl http://localhost/health

# Base de données
docker-compose -f docker-compose.prod.yml exec db pg_isready -U zugfahrt_user

# Redis
docker-compose -f docker-compose.prod.yml exec redis redis-cli ping
```

### URLs de contrôle

| Service          | URL                     | Credentials         |
| ---------------- | ----------------------- | ------------------- |
| **Application**  | http://localhost        | -                   |
| **Health Check** | http://localhost/health | -                   |
| **Prometheus**   | http://localhost:9090   | -                   |
| **Grafana**      | http://localhost:3000   | admin / (from .env) |

## 📊 Monitoring

### Métriques Disponibles

- **Application** : JVM, HTTP requests, custom business metrics
- **Base de données** : Connexions, requêtes, performance
- **Redis** : Utilisation mémoire, hits/miss ratio
- **Nginx** : Requests per second, response times
- **Système** : CPU, RAM, disque, réseau

### Grafana Dashboards

1. **Application Dashboard** - Métriques Spring Boot
2. **Infrastructure Dashboard** - PostgreSQL, Redis, Nginx
3. **Business Dashboard** - Métriques métier spécifiques

## 🔒 Sécurité

### Checklist Sécurité

- ✅ **JWT secrets** générés de façon sécurisée (>32 chars)
- ✅ **Mots de passe** base de données complexes
- ✅ **HTTPS** configuré avec certificats valides
- ✅ **CORS** restreint aux domaines autorisés
- ✅ **Rate limiting** configuré sur Nginx
- ✅ **Headers sécurité** appliqués
- ✅ **Ports** non nécessaires fermés
- ✅ **Logs** centralisés et monitored

### Ports Exposés

| Port | Service     | Accès      |
| ---- | ----------- | ---------- |
| 80   | Nginx HTTP  | Public     |
| 443  | Nginx HTTPS | Public     |
| 3000 | Grafana     | Admin only |
| 9090 | Prometheus  | Admin only |

## 💾 Sauvegardes

### Sauvegarde Automatique

```bash
# Créer une sauvegarde
./deploy-prod.sh backup

# Sauvegardes automatiques (cron)
# Ajouter à crontab -e
0 2 * * * /path/to/deploy-prod.sh backup
```

### Restauration

```bash
# Arrêter l'application
docker-compose -f docker-compose.prod.yml stop app

# Restaurer la base de données
cat backups/backup_20231128_120000.sql | docker-compose -f docker-compose.prod.yml exec -T db psql -U zugfahrt_user zugfahrt_prod

# Redémarrer
docker-compose -f docker-compose.prod.yml start app
```

## 🔄 Mise à jour

### Mise à jour avec zéro downtime

```bash
# 1. Sauvegarder
./deploy-prod.sh backup

# 2. Pull dernières modifications
git pull origin main

# 3. Redéployer
./deploy-prod.sh deploy
```

### Rollback

```bash
# En cas de problème
./deploy-prod.sh rollback
```

## 🛠️ Dépannage

### Problèmes Courants

**Application ne démarre pas :**

```bash
# Vérifier les logs
docker-compose -f docker-compose.prod.yml logs app

# Vérifier les variables d'environnement
docker-compose -f docker-compose.prod.yml exec app env | grep -E "(JWT|DB|REDIS)"
```

**Base de données inaccessible :**

```bash
# Tester la connexion
docker-compose -f docker-compose.prod.yml exec app nc -zv db 5432

# Vérifier les logs DB
docker-compose -f docker-compose.prod.yml logs db
```

**SSL/HTTPS issues :**

```bash
# Vérifier les certificats
openssl x509 -in ssl/cert.pem -text -noout

# Tester SSL
openssl s_client -connect votre-domaine.com:443
```

### Commandes Utiles

```bash
# État détaillé des services
docker-compose -f docker-compose.prod.yml ps

# Utilisation des ressources
docker stats

# Logs en temps réel
docker-compose -f docker-compose.prod.yml logs -f

# Redémarrer un service
docker-compose -f docker-compose.prod.yml restart app

# Shell dans un conteneur
docker-compose -f docker-compose.prod.yml exec app bash
```

## 📞 Support

### Monitoring et Alertes

- **Grafana** : Dashboard avec alertes configurées
- **Prometheus** : Métriques détaillées et règles d'alerting
- **Health checks** : Vérifications automatiques toutes les 30s

### Logs

- **Application** : `/app/logs/zugfahrt-app.log`
- **Nginx** : `./logs/nginx/`
- **Docker** : `docker-compose logs`

---

## 🎉 Déploiement Terminé !

Votre application **Zugfahrt Pro** est maintenant déployée en production avec :

✅ **Sécurité renforcée** - JWT, HTTPS, rate limiting  
✅ **Haute disponibilité** - Health checks, auto-restart  
✅ **Performance optimisée** - Cache Redis, compression  
✅ **Monitoring complet** - Métriques, dashboards, alertes  
✅ **Sauvegardes automatiques** - Base de données protégée

**🔗 Accès rapide :**

- **App** : https://votre-domaine.com
- **Monitoring** : http://localhost:3000 (Grafana)
- **Métriques** : http://localhost:9090 (Prometheus)
