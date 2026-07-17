-- meta-module: 2026/Q1
-- makes the Q1 tier and its upstream (H1, annual) tiers' modules available
prepend_path("MODULEPATH", "@@SPACK_INSTALL_ROOT@@/2026/annual/modules/lmod")
prepend_path("MODULEPATH", "@@SPACK_INSTALL_ROOT@@/2026/H1/modules/lmod")
prepend_path("MODULEPATH", "@@SPACK_INSTALL_ROOT@@/2026/Q1/modules/lmod")
