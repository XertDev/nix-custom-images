{ python3, python3Packages, fetchFromGitHub, package }:
python3.pkgs.buildPythonPackage {
  pname = "fava_investor";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "redstreet";
    repo = "fava_investor";
    rev = "2ebbd03aedfe0ecb205ee8ec1ec18bbfd0808f06";
    hash = "sha256-BEmZmr4cerYQLGbssaXvIYNVJUg8y0Z4kXBLCQquKLg=";
  };
  pyproject = true;

  doCheck = false;
  doInstallCheck = false;

  propagatedBuildInputs = with python3Packages; [
    package
    tabulate
    yfinance
    click-aliases
  ];

  build-system = with python3Packages; [ poetry-core hatch-vcs hatchling ];
}
