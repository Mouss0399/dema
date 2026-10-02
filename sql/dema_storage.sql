-- =====================================================================
-- Dema — dépôt des captures de paiement (Supabase Storage)
-- À passer une seule fois, dans le SQL Editor, après dema_api.sql.
-- =====================================================================
-- Ce que ça fait :
--   • crée un casier « preuves » privé, limité à 2 Mo par image ;
--   • autorise la page employé à y DÉPOSER, sans jamais pouvoir relire ;
--   • réserve la lecture au compte authentifié du traiteur.
-- Autrement dit : personne ne peut fouiller les captures des autres depuis
-- la page, même en connaissant la clé publique — elle est dans le code.
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('preuves', 'preuves', false, 2097152,
        array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
   set public             = excluded.public,
       file_size_limit    = excluded.file_size_limit,
       allowed_mime_types = excluded.allowed_mime_types;

-- Dépôt : la page employé, qui parle avec la clé publique (rôle anon).
drop policy if exists "preuves depot" on storage.objects;
create policy "preuves depot" on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'preuves');

-- Lecture : seulement un compte connecté — l'écran du traiteur.
-- Aucune politique de lecture pour anon : la page qui dépose ne relit rien.
drop policy if exists "preuves lecture" on storage.objects;
create policy "preuves lecture" on storage.objects
  for select to authenticated
  using (bucket_id = 'preuves');

-- Pas de politique update/delete : une capture déposée n'est ni remplaçable
-- ni effaçable depuis la page. Le ménage se fait côté serveur (voir plus bas).

-- ---------------------------------------------------------------------
-- Vérification
-- ---------------------------------------------------------------------
select id, public, file_size_limit, allowed_mime_types
  from storage.buckets where id = 'preuves';

select policyname, roles, cmd
  from pg_policies
 where schemaname = 'storage' and tablename = 'objects'
   and policyname like 'preuves%'
 order by policyname;

-- ---------------------------------------------------------------------
-- Ménage. Une capture ne sert qu'en cas de doute, et le doute ne dure pas
-- deux mois. À lancer à la main de temps en temps, ou par un cron Supabase
-- plus tard. 500 Mo gratuits : à 80 ko l'image et 200 règlements par
-- semaine, la purge n'est pas urgente, mais elle évitera la surprise.
-- ---------------------------------------------------------------------
-- delete from storage.objects
--  where bucket_id = 'preuves' and created_at < now() - interval '60 days';
