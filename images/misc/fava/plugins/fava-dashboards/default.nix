{ python3, python3Packages, fetchFromGitHub, package }:
python3.pkgs.buildPythonPackage {
  pname = "fava-dashboards";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "andreasgerstmayr";
    repo = "fava-dashboards";
    rev = "5814d8c98ec8646035b1c79f3961a1df61764d3c";
    hash = "sha256-/ma7ZJtQ5D+kB5fMUm3gG3q6CcnpLcPhA3nmYKuYG1U=";
  };
  pyproject = true;

  doCheck = false;
  doInstallCheck = false;

  propagatedBuildInputs = with python3Packages; [ package pyyaml ];

  build-system = with python3Packages; [ poetry-core hatch-vcs hatchling ];
}
