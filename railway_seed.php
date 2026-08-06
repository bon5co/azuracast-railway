<?php

declare(strict_types=1);

/**
 * Seed the first AzuraCast super administrator from the environment.
 *
 * AzuraCast's setup wizard creates the first account with no authentication at
 * all: App\Controller\Frontend\SetupController::registerAction serves and
 * accepts POSTs from anybody as long as the users table is empty. On Railway
 * the public HTTPS URL exists as soon as the deploy goes healthy, so that
 * window is open to whoever reaches the URL first. Creating the account during
 * boot closes it before the service ever answers a request.
 *
 * Runs once per boot; a no-op when any account already exists.
 */

require '/var/azuracast/www/vendor/autoload.php';

$email = trim((string)getenv('AZURACAST_ADMIN_EMAIL'));
$password = (string)getenv('AZURACAST_ADMIN_PASSWORD');

if ('' === $email || '' === $password) {
    fwrite(STDERR, "[railway] AZURACAST_ADMIN_EMAIL/PASSWORD unset; refusing to boot a claimable instance.\n");
    exit(1);
}

$environment = App\AppFactory::buildEnvironment();
$di = App\AppFactory::buildContainer(App\AppFactory::createContainerBuilder($environment));

/** @var Doctrine\ORM\EntityManagerInterface $em */
$em = $di->get(Doctrine\ORM\EntityManagerInterface::class);

$existing = (int)$em->createQuery('SELECT COUNT(u.id) FROM App\Entity\User u')->getSingleScalarResult();
if ($existing > 0) {
    echo "[railway] $existing account(s) already exist; leaving them alone.\n";
    exit(0);
}

/** @var App\Entity\Repository\RolePermissionRepository $permissionRepo */
$permissionRepo = $di->get(App\Entity\Repository\RolePermissionRepository::class);

$user = new App\Entity\User();
$user->email = $email;
$user->name = 'Administrator';
$user->setNewPassword($password);
$user->roles->add($permissionRepo->ensureSuperAdministratorRole());

$em->persist($user);
$em->flush();

echo "[railway] Seeded super administrator {$email}; /setup/register is now closed.\n";
