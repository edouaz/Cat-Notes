# Supabase — configuration et validation

Le cloud n’a pas été testé contre un service : aucun projet, compte ni identifiant n’a été fourni. Le mode local fonctionne sans cette configuration.

1. Créer un projet de développement Supabase. Activer l’authentification e-mail/mot de passe et définir la confirmation d’e-mail selon le besoin.
2. Appliquer `supabase/migrations/202610210001_notebooks.sql` via l’éditeur SQL ou Supabase CLI. Ne pas appliquer deux fois cette migration non idempotente.
3. Copier `Config/Supabase.example.plist` vers `Config/Supabase.plist` (ignoré par Git). Renseigner l’URL HTTPS et **uniquement une clé publishable**, ou une ancienne clé JWT de rôle `anon`. Le chargeur refuse les clés secrètes et les JWT de rôle privilégié.
4. Exécuter `python3 scripts/generate-project.py` pour embarquer la configuration et reconstruire l’app.
5. Dans Compte et cloud : créer/confirmer un compte, se connecter puis associer explicitement la bibliothèque. Une bibliothèque locale est liée à un seul compte pour éviter d’envoyer les documents d’A à B après changement de session.

Les tokens de session sont dans le Trousseau, accessibles après premier déverrouillage sur cet appareil uniquement. Ni mot de passe ni token ne sont journalisés. La déconnexion supprime la session locale. Elle ne supprime pas les carnets.

## Données et reprise

- Bucket `notebooks` privé, fichiers natifs incluant dessins et PDF source. Limite de fichier initiale : 150 Mio ; l’import local est plafonné à 150 Mo.
- Postgres contient des identifiants de carnet/révision/parent, SHA-256, chemins et dates. Aucun binaire.
- Une révision et son objet Storage sont immuables. Aucune policy UPDATE/DELETE n’est ouverte. Seul le propriétaire peut lire/insérer ses données.
- Les métadonnées locales sauvegardées sont la source de la file d’envoi : date modifiée puis checksum comparés à l’état de synchronisation conservé localement. Analyse toutes les 30 secondes **au premier plan**, reprise au prochain passage/relancement. L’écriture n’attend jamais le réseau. Ce n’est pas un service de transfert garanti lorsque l’app est suspendue par iOS.
- L’objet est écrit avant la ligne de révision. Une interruption entre les deux peut laisser un objet orphelin ; une maintenance serveur sera nécessaire avant production.
- Toute révision distante inconnue est importée avec de nouveaux identifiants locaux, sans remplacement d’un carnet. En cas de divergence, les deux notes subsistent et la version distante est nommée comme telle. La fusion et le regroupement d’un historique distant en une seule note restent à faire : ce protocole conservateur produit des copies lors des mises à jour provenant d’un autre appareil.
- L’import d’un carnet est publié uniquement après l’écriture de toutes ses ressources. Une mutation concurrente locale annule la publication et conserve les données locales. Des ressources orphelines peuvent subsister sans être visibles.

**Ce cloud est un prototype sûr contre l’écrasement, pas une synchronisation P1 validée.** Il faut encore automatiser les coupures/réessais, limiter les copies de révisions, tester le renouvellement de session, les conflits multidispositifs et la pagination contre un vrai service. L’état de suivi utilise UserDefaults et n’est pas une transaction avec la bibliothèque : un arrêt brutal peut produire une copie supplémentaire, pas remplacer l’original.

## Validation SQL locale exécutée

`python3 scripts/test-rls-local.py` a réussi sur PostgreSQL16.14 dans un cluster jetable, socket Unix sans écoute réseau, supprimé ensuite. Il applique la vraie migration et vérifie dans les deux sens propriétaire/A/B : SELECT/INSERT autorisés au propriétaire, invisibilité et refus d’insertion intercompte, métadonnées immuables, fichiers immuables, accès anonyme refusé. Les schémas/fonctions `auth` et `storage` sont des stubs minimaux ; ce test ne vérifie pas Supabase Auth, l’API HTTP Storage, les limites du service ou les policies préexistantes d’un projet réel.

## Test d’isolation à deux comptes sur Supabase

Sur un projet **jetable**, créer/confirmer deux utilisateurs distincts. Définir dans l’environnement :

```
SUPABASE_URL
SUPABASE_PUBLISHABLE_KEY
TEST_A_EMAIL
TEST_A_PASSWORD
TEST_B_EMAIL
TEST_B_PASSWORD
```

Exécuter `python3 scripts/check-rls.py`. Le script ne journalise pas les secrets. Il vérifie dans les deux sens : upload/lecture propriétaire, invisibilité des métadonnées de l’autre, refus de téléchargement de son binaire, refus des modifications et de l’usurpation d’owner. Il laisse volontairement des fixtures immuables dans le projet jetable. Ces assertions HTTP n’ont pas été exécutées faute de comptes.

Les policies doivent être auditées avec celles déjà présentes sur un projet existant : des policies permissives supplémentaires pourraient élargir l’accès. L’accès anonyme doit aussi être vérifié après déploiement.

Références consultées le 21 octobre 2026 : [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [Storage Swift](https://supabase.com/docs/reference/swift/storage-from-upload). Vérifier [les quotas et tarifs](https://supabase.com/pricing) avant lancement ; aucune gratuité à l’échelle n’est supposée.
