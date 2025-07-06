{ python3, python3Packages, fetchFromGitHub, beanprice }:
python3.pkgs.buildPythonPackage {
  pname = "beangrow";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "beancount";
    repo = "beangrow";
    rev = "bd1bf195648dda73c47af945a5191ec16b2ab557";
    hash = "sha256-KgNTQXcck1G7GvondJbvgKBT7REYHZ5Hp3eJZ9IQFDs=";
  };
  pyproject = true;

  doCheck = false;
  doInstallCheck = false;

  propagatedBuildInputs = with python3Packages; [
    beancount
    beanprice
    matplotlib
    scipy
    pandas
    protobuf
  ];

  build-system = with python3Packages; [ poetry-core setuptools ];
}
