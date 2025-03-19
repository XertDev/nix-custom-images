{ pkgs, mkImage, ... }:
{
	default = mkImage {
	  options = {
	  };

	  image = { ... }: {
	    name = "hello";
	    config = {
	      Cmd = [ "${pkgs.hello}/bin/hello" ];
	    };
	  };
	};
}