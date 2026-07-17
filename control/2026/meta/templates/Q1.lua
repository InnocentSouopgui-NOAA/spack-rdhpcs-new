-- meta-module: 2026/Q1
-- makes the Q1 tier and its upstream (H1, annual) tiers' modules available
prepend_path("MODULEPATH", "@@SPACK_INSTALL_ROOT@@/2026/annual/modules/lmod/@@SPACK_LMOD_ARCH@@/Core")
prepend_path("MODULEPATH", "@@SPACK_INSTALL_ROOT@@/2026/H1/modules/lmod/@@SPACK_LMOD_ARCH@@/Core")
prepend_path("MODULEPATH", "@@SPACK_INSTALL_ROOT@@/2026/Q1/modules/lmod/@@SPACK_LMOD_ARCH@@/Core")
