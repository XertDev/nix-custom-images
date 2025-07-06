{ python3, python3Packages, fetchFromGitHub, package, beangrow }:
python3.pkgs.buildPythonPackage {
  pname = "fava-portfolio-returns";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "andreasgerstmayr";
    repo = "fava-portfolio-returns";
    rev = "61cb8be4bfed58b50948c510cc1d85a74946636e";
    hash = "sha256-JjU4rg5dP0r9Wi5FNfABnQhOk7JtIg623J+h9PLCm28=";
  };
  pyproject = true;

  doCheck = false;
  doInstallCheck = false;

  propagatedBuildInputs = [ package beangrow ];

  build-system = with python3Packages; [ poetry-core hatch-vcs hatchling ];
}
