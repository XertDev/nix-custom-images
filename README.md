# Nix Custom Images

[![Build all images with default](https://img.shields.io/github/actions/workflow/status/XertDev/nix-custom-images/build-test.yaml?label=Build)](https://github.com/XertDev/nix-custom-images/actions/workflows/build-test.yaml)
![License](https://img.shields.io/github/license/XertDev/nix-custom-images)

Custom OCI images with included config

---

## Features

- **Easy configuration**: Configuration which uses module system from NixOS. Options similar to services.* from NixOS
- **Nix snapshotter support**: Some images have support for nix-snapshotter

---

## Example
```nix
images.tandoor.default {
  uid = 1000;
  gid = 1000;

  extraConfig = {
    REMOTE_USER_AUTH=1;
  };
}
```

## Available options
Available images and supported options can be found at [generated search page](https://xertdev.github.io/nix-custom-images/)

---
## License

This project is licensed under the [MIT License](LICENSE).