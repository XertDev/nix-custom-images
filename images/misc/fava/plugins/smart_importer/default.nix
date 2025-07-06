{ python3, python3Packages, fetchFromGitHub }:
python3.pkgs.buildPythonPackage rec {
  pname = "smart_importer";
  version = "1.1";

  src = fetchFromGitHub {
    owner = "beancount";
    repo = "smart_importer";
    rev = "v${version}";
    hash = "sha256-UODqDgZI7RP95iaW8/2RAG8rqNcMyRLyGSFXd+iQEJM=";
  };
  pyproject = true;

  doCheck = false;
  doInstallCheck = false;

  nativeBuildInputs = with python3Packages; [ setuptools_scm ];

  propagatedBuildInputs = with python3Packages; [
    beancount
    beangulp
    scikit-learn
    numpy
  ];

  build-system = with python3Packages; [ poetry-core setuptools ];
}
