pkgname=ez2lazer-git
url="https://github.com/SK-la/Ez2Lazer"
pkgrel=1
pkgver=2026.2.17.r38.gf95c9eb48c
pkgdesc="Ez to Lazer(Pursue the Ez2Ac style in the lazer)做一个炫酷的客户端"
arch=("x86_64")
license=("MIT")
depends=(
    'dotnet-runtime'
    )
makedepends=('dotnet-sdk'
    "python311")
source=(
    "osu::git+https://github.com/SK-la/Ez2Lazer.git#branch=locmain"
    "osu-framework::git+https://github.com/SK-la/osu-framework.git#branch=locmain"
    "osu-resources::git+https://github.com/SK-la/osu-resources.git#branch=locmain"
    "osu-ez2lazer"
    "osu-ez2lazer.desktop"
    "lazer.png")

sha256sums=('SKIP'
    'SKIP'
    'SKIP'
    '9ff0894014e1ca9d9096e0050f2e4e36afe8f14275249045376c7dff150274d3'
    '17a504de02a94727584e77c90d93b6bf072dd40f339e05fb2df038f67d9a9d6d'
    '30cf4df3fd76006b08a0bcb6a325fb2fdcf6a4371f77001da3c38cbce871bd51')

pkgver() {
    cd osu
    git describe --long --tags | sed 's/\([^-]*-g\)/r\1/;s/-/./g'
}

build() {
    $srcdir/osu/publish-linux.py --no-zip --outroot $srcdir
    ls $srcdir
}

package() {
    mkdir -p "$pkgdir"/opt/osu-ez2lazer
    cp -dr --no-preserve=ownership "$srcdir"/Ez2Lazer_release_x64/* "$pkgdir"/opt/osu-ez2lazer
    install -D -m755 osu-ez2lazer "$pkgdir"/usr/bin/osu-ez2lazer

    install -D -m644 osu-ez2lazer.desktop "$pkgdir"/usr/share/applications/osu-ez2lazer.desktop
    install -D -m644 lazer.png "$pkgdir"/usr/share/pixmaps/ez2lazer.png
}
