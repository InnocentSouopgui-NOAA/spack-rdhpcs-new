-- meta-module: 2026/H1
-- makes the H1 tier and its upstream (annual) tier's modules available
prepend_path("MODULEPATH", "@@SPACK_INSTALL_ROOT@@/2026/annual/modules/lmod")
prepend_path("MODULEPATH", "@@SPACK_INSTALL_ROOT@@/2026/H1/modules/lmod")
