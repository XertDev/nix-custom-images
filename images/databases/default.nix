{ callPackage, ... }: {
  openldap = callPackage ./openldap { };
  postgres = callPackage ./postgres { };
}
