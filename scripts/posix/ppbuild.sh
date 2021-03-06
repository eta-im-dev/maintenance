#!/bin/bash

#CONSTANTS/КОНСТАНТЫ
home=${HOME:-/home/$USER} #домашний каталог
psi_version="0.16" #не менять без необходимости, нужно для пакетирования
bindirs="/usr/bin
/usr/local/bin
${home}/bin" #список каталогов где могут быть найдены бинарники
qconf_cmds="qconf
qconf-qt4
qconf-qt5
qt-qconf" #список возможных имён бинарника qconf
lib_prefixes="/usr/lib
/usr/lib64
/usr/local/lib
/usr/local/lib64" #список каталогов для поиска библиотек
def_prefix="/usr" #префикс для сборки пси+
libpsibuild_url="https://raw.github.com/psi-plus/maintenance/master/scripts/posix/libpsibuild.sh"
#DEFAULT OPTIONS/ОПЦИИ ПО УМОЛЧАНИЮ
no_enchant="--disable-enchant"
iswebkit=""
use_iconsets="system clients activities moods affiliations roster"
isoffline=0
skip_invalid=0
use_plugins="*"
let cpu_count=$(grep -c ^processor /proc/cpuinfo)+1
#
#COLORS
red="\e[0;31m"
green="\e[0;32m"
nocolor="\x1B[0m"
pink="\x1B[01;91m"
yellow="\x1B[01;93m"
blue="\x1B[01;94m"
#

#VARIABLES/ПЕРЕМЕННЫЕ
#каталог где будет лежать скрипт libpsibuild.sh и каталог buildpsi(по умолчанию)
workdir=${home}/github
#значение переменной buildpsi по умолчанию
default_buildpsi=${workdir}/psi 
#имя временного каталога для пакетирования
inst_suffix=tmp
#префикс CMAKE по умолчанию
DEF_CMAKE_INST_PREFIX="${home}/.local"
#каталог плагинов в префиксе по умолчанию
DEF_CMAKE_INST_SUFFIX="share/psi+/plugins"
#список плагинов для сборки через ";" (otrplugin;cleanerplugin и.т.д.)
DEF_PLUG_LIST="ALL"
#тип сборки плагинов
DEF_CMAKE_BUILD_TYPE="Release"
#Qt5
QT4_BUILD="OFF"

#WARNING: следующие переменные будут изменены в процессе работы скрипта автоматически
buildpsi=${default_buildpsi} #инициализация переменной
orig_src=${buildpsi}/build #рабочий каталог для компиляции psi+
patches=${buildpsi}/git-plus/patches #путь к патчам psi+, необходим для разработки
inst_path=${buildpsi}/${inst_suffix} #только для пакетирования
cmake_files_dir=${buildpsi}/psi-plus-cmake #файлы CMAKE для сборки плагинов
#

#ENVIRONMENT VARIABLES/ПЕРЕМЕННЫЕ СРЕДЫ
psi_datadir=${home}/.local/share/psi+
psi_cachedir=${home}/.cache/psi+
psi_homeplugdir=${psi_datadir}/plugins
#

#CONFIG FILE PATH/ПУТЬ К ФАЙЛУ НАСТРОЕК
config_file=${home}/.config/psibuild.cfg

#PLUGINS_BUILD_LOG/ЛОГ ФАЙЛ СБОРКИ ПЛАГИНОВ
plugbuild_log=${orig_src}/plugins.log
#

#RPM_VARIABLES/ПЕРЕМЕННЫЕ ДЛЯ СБОРКИ RPM ПАКЕТОВ
rpmbuilddir=${home}/rpmbuild
rpmspec=${rpmbuilddir}/SPECS
rpmsrc=${rpmbuilddir}/SOURCES
#

#значения по умолчанию для поиска утилиты qconf
qconf_bin="qconf"
qconf_dir="/usr/bin"
#

find_qconf ()
{
  local isfound=0
  for cmd_item in ${qconf_cmds}; do
    for bin_path in ${bindirs}; do
    if [ -f "${bin_path}/${cmd_item}" ]; then
      qconf_dir="${bin_path}"
      qconf_bin="${bin_path}/${cmd_item}"
      isfound=1
      break
    fi
    done
    if [ ${isfound} -eq 1 ]; then
      echo -e "${pink}QConf utility found:${nocolor} ${qconf_bin}"; echo ""
      break
    fi
  done
  if [ ${isfound} -eq 0 ] || [ -z "${qconf_bin}" ]; then
    echo -e "Enter the absolute path to qconf binary (${pink}Example:${nocolor} /home/me/qconf):"
    read qconf_bin
  fi
}

find_ccache ()
{
  local ccache_path=""
  for prefix_path in ${lib_prefixes}; do
    if [ -d "${prefix_path}/ccache/bin" ]; then
      if [ -f "${prefix_path}/ccache/bin/g++" ]; then
        ccache_path=${prefix_path}/ccache/bin
        break
      fi
    fi
  done
  
  if [ ! -z "${ccache_path}" ]; then
    PATH="${ccache_path}:${PATH}"
    QMAKE_CCACHE_CMD="QMAKE_CXX=ccache g++"
  fi
}
#
quit ()
{
  break
}
#
read_options ()
{
  local pluginlist=""
  if [ -f ${config_file} ]; then
    local inc=0
    while read -r line; do
      case ${inc} in
      "0" ) iswebkit=$(echo ${line});;
      "1" ) use_iconsets=$(echo ${line});;
      "2" ) isoffline=$(echo ${line});;
      "3" ) skip_invalid=$(echo ${line});;
      "4" ) pluginlist=$(echo ${line});;
      "5" ) no_enchant=$(echo ${line});;
      "6" ) buildpsi=$(echo ${line});;
      esac
      let "inc+=1"
    done < ${config_file}
    if [ "$pluginlist" == "all" ]; then
      use_plugins="*"
    else
      use_plugins=${pluginlist}
    fi
    if [ -z "${buildpsi}" ]; then
      buildpsi=${default_buildpsi}
    fi
    if [ "${buildpsi:0:5}" == "\$HOME" ]; then
      buildpsi=${home}/${buildpsi:6}
    fi
  fi
  update_variables
}
#
set_options ()
{
  PSI_DIR="${buildpsi}"
  ICONSETS=${use_iconsets}
  WORK_OFFLINE=${WORK_OFFLINE:-$isoffline}
  PATCH_LOG=""
  SKIP_INVALID_PATCH="${SKIP_INVALID_PATCH:-$skip_invalid}"
  CONF_OPTS="${iswebkit} ${no_enchant}"
  INSTALL_ROOT="${INSTALL_ROOT:-$def_prefix}"
  QCONFDIR=${qconf_dir}
  PLUGINS="${PLUGINS:-$use_plugins}"
}
#
update_variables ()
{
  orig_src=${buildpsi}/build
  patches=${buildpsi}/git-plus/patches
  inst_path=${buildpsi}/${inst_suffix}
  cmake_files_dir=${buildpsi}/psi-plus-cmake
}
#
die() { echo "$@"; exit 1; }
#
check_libpsibuild ()
{
  cd ${workdir}
  if [ "$isoffline" = 0 ]; then
    echo -e "${blue}**libpsibuild.sh library updates check**${nocolor}"; echo ""
    wget --output-document="libpsibuild.sh.new" --no-check-certificate ${libpsibuild_url};
    if [ "$(diff -q libpsibuild.sh libpsibuild.sh.new)" ] || [ ! -f "${workdir}/libpsibuild.sh" ]
    then
      echo -e "${blue}**libpsibuild.sh library has been updated**${nocolor}"; echo ""
      mv -f ${workdir}/libpsibuild.sh.new ${workdir}/libpsibuild.sh
    else
      echo -e "${blue}**you have the last version of libpsibuild.sh library**${nocolor}"; echo ""  
      rm -f ${workdir}/libpsibuild.sh.new
    fi
    chmod u+x ${workdir}/libpsibuild.sh
  fi
}
#
run_libpsibuild ()
{
  if [ ! -z "$1" ]; then
    cd ${workdir}
    . ./libpsibuild.sh
    check_env $CONF_OPTS
    $1
  fi
}
#
check_dir ()
{
  if [ ! -z "$1" ]; then
    if [ ! -d "$1" ]; then
      mkdir -pv "$1"
    fi
  fi
}
#
down_all ()
{
  check_dir ${buildpsi}/git
  check_dir ${buildpsi}/git-plus
  check_dir ${buildpsi}/plugins
  run_libpsibuild fetch_all
}
#
prepare_src ()
{
  down_all
  run_libpsibuild prepare_workspace
  run_libpsibuild prepare_all
  echo -e "${blue}Do you want to apply psi-new-history.patch${nocolor} ${pink}[y/n(default)]${nocolor}"
  read ispatch
  if [ "${ispatch}" == "y" ]; then
    cd ${orig_src}
    patch -p1 --input=${patches}/dev/psi-new-history.patch
    cd ${workdir}
  fi
}
#
backup_tar ()
{
  echo "Backup ${buildpsi##*/} into ${buildpsi%/*}/${buildpsi##*/}.tar.gz started..."
  cd ${buildpsi%/*}
  tar -pczf ${buildpsi##*/}.tar.gz ${buildpsi##*/}
  echo "Backup finished..."; echo " "
}
#
prepare_tar ()
{
  check_dir ${rpmbuilddir}
  check_dir ${rpmsrc}
  check_dir ${rpmspec}
  echo "Preparing Psi+ source package to build RPM..."
  local rev=$(cd ${buildpsi}/git-plus/; echo $(($(git describe --tags | cut -d - -f 2))))
  local tar_name=psi-plus-${psi_version}.${rev}
  local new_src=${buildpsi}/${tar_name}
  cp -r ${orig_src} ${new_src}
  if [ -d ${new_src} ]; then
    cd ${buildpsi}
    tar -sczf ${tar_name}.tar.gz ${tar_name}
    rm -r -f ${new_src}
    if [ -d ${rpmsrc} ]; then
      if [ -f "${rpmsrc}/${tar_name}.tar.gz" ]; then
        rm -f ${rpmsrc}/${tar_name}.tar.gz
      fi
      cp -f ${buildpsi}/${tar_name}.tar.gz ${rpmsrc}
    fi
    echo "Preparing completed"
  fi
}
#
compile_psiplus ()
{
  curd=$(pwd)
  prepare_src
  cd ${orig_src}
  echo "***Build started***">${buildpsi}/build.log
  echo "--Starting ${qconf_bin}">>${buildpsi}/build.log
  ${qconf_bin} 2>>${buildpsi}/build.log
  args="--prefix=/usr --enable-plugins --enable-whiteboarding ${iswebkit} ${no_enchant}"
  echo "--Starting configure with args
${args}  
">>${buildpsi}/build.log
  ./configure ${args} 2>>${buildpsi}/build.log
  echo "--Starting make">>${buildpsi}/build.log
  make -j${cpu_count} 2>>${buildpsi}/build.log || echo -e "${red}There were errors. Open ${buildpsi}/build.log to see${nocolor}"
  echo "***Build finished***">>${buildpsi}/build.log
  cd ${curd}
}
#
qmakecmd ()
{
  if [ -f "/usr/bin/qmake" ] || [ -f "/usr/local/bin/qmake" ]; then
    qmake || die
  else
    if [ -f "/usr/bin/qmake-qt4" ] || [ -f "/usr/local/bin/qmake-qt4" ]; then
      qmake-qt4 || die
    else
      echo -e "${red}ERROR qmake not found${nocolor}"
    fi
  fi
}
#
build_plugins ()
{
  if [ ! -f "${orig_src}/psi.pro" ]; then
    prepare_src
  fi
  local tmpplugs=${orig_src}/plugins
  check_dir ${tmpplugs}
  local plugins=$(find ${orig_src}/src/plugins -name '*plugin.pro' -print0 | xargs -0 -n1 dirname)
  for pplugin in ${plugins}; do
    make_plugin ${pplugin} 2>>${plugbuild_log}
  done
  echo "*******************************"
  echo "Plugins compiled succesfully!!!"
  echo "*******************************"
  echo -e "${blue}Do you want to install psi+ plugins into ${psi_homeplugdir}${nocolor} ${pink}[y/n(default)]${nocolor}"
  read isinstall
  if [ "${isinstall}" == "y" ]; then
    check_dir ${psi_homeplugdir}
    cp -vf ${buildpsi}/build/plugins/*.so ${psi_homeplugdir}/
  fi
  echo "********************************"
  echo "Plugins installed succesfully!!!"
  echo "********************************"
  cd ${workdir}
}
#
make_plugin ()
{
  if [ ! -z "$1" ]; then
    local currdir=$(pwd)
    cd "$1"
    if [ ! -z "$(ls .obj | grep -e '.o$')" ]; then make clean && make distclean; fi
    qmakecmd -t ${QMAKE_CCACHE_CMD} && make -j${cpu_count} && cp -f *.so ${tmpplugs}/
    cd ${currdir}
  fi
}
#
fetch_cmake_files ()
{
  local repo_url="https://github.com/Vitozz/psi-plus-cmake.git"
  
  cd ${buildpsi}
  if [ ! -d "${cmake_files_dir}" ]; then
    check_dir ${cmake_files_dir}
    git clone ${repo_url} ${cmake_files_dir}
  else
    cd ${cmake_files_dir}
    git reset --hard
    git pull
  fi
  cd ${buildpsi}
}
#
build_cmake_plugins ()
{
  echo_done() {
    echo " "
    echo "********************************"
    echo "Plugins installed succesfully!!!"
    echo "********************************"
    echo " "
  }
  local pl_preffix=${DEF_CMAKE_INST_PREFIX}
  local pl_suffix=${DEF_CMAKE_INST_SUFFIX}
  fetch_cmake_files
  if [ ! -f "${orig_src}/psi.pro" ]; then
    prepare_src
  fi
  check_dir ${orig_src}
  cp -rf ${cmake_files_dir}/* ${orig_src}/
  cd ${orig_src}
  local b_dir=${orig_src}/build
  check_dir ${b_dir}
  cd ${b_dir}
  echo -e "${blue}Do you want to install psi+ plugins into ${psi_homeplugdir}${nocolor} ${pink}[y/n(default)]${nocolor}"
  read isinstall
  if [ "${isinstall}" != "y" ]; then
    pl_preffix=${orig_src}
    pl_suffix="plugins"
  fi  
  local cmake_flags="-DCMAKE_BUILD_TYPE=${DEF_CMAKE_BUILD_TYPE} -DCMAKE_INSTALL_PREFIX=${pl_preffix} -DONLY_PLUGINS=ON -DPLUGINS_PATH=${pl_suffix} -DBUILD_PLUGINS=${DEF_PLUG_LIST} -DBUILD_DEV=OFF -DQT4_BUILD=${QT4_BUILD}"
  echo " "; echo "Build psi+ plugins using CMAKE started..."; echo " "
  cmake ${cmake_flags} ..
  make -j${cpu_count} && make install && echo_done
  cd ${orig_src}
  rm -rf ${b_dir}
}
#
build_deb_package ()
{
  if [ ! -f "${orig_src}/psi-plus" ]; then
    compile_psiplus
  fi
  echo "Building Psi+ DEB package with checkinstall"
  local rev=$(cd ${buildpsi}/git-plus/; echo $(($(git describe --tags | cut -d - -f 2))))
  local desc='Psi is a cross-platform powerful Jabber client (Qt, C++) designed for the Jabber power users.
Psi+ - Psi IM Mod by psi-dev@conference.jabber.ru.'
  cd ${orig_src}
  echo "${desc}" > description-pak
  local requires=' "libaspell15 (>=0.60)", "libc6 (>=2.7-1)", "libgcc1 (>=1:4.1.1)", "libqca2", "libqt4-dbus (>=4.4.3)", "libqt4-network (>=4.4.3)", "libqt4-qt3support (>=4.4.3)", "libqt4-xml (>=4.4.3)", "libqtcore4 (>=4.4.3)", "libqtgui4 (>=4.4.3)", "libstdc++6 (>=4.1.1)", "libx11-6", "libxext6", "libxss1", "zlib1g (>=1:1.1.4)" '
  sudo checkinstall -D --nodoc --pkgname=psi-plus --pkggroup=net --pkgversion=${psi_version}.${rev} --pkgsource=${orig_src} --maintainer="thetvg@gmail.com" --requires="${requires}"
  cp -f ${orig_src}/*.deb ${buildpsi}
}
#
prepare_spec ()
{
  local rev=$(cd ${buildpsi}/git-plus/; echo $(($(git describe --tags | cut -d - -f 2))))
  if [ ! -z ${qconf_bin} ] && [ -f "${qconf_bin}" ]; then
    qconfcmd=${qconf_bin}
  fi
  echo "Creating psi.spec file..."
  local specfile="Summary: Client application for the Jabber network
Name: psi-plus
Version: ${psi_version}.${rev}
Release: 1
License: GPL
Group: Applications/Internet
URL: http://code.google.com/p/psi-dev/
Source0: %{name}-%{version}.tar.gz


BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root


BuildRequires: openssl-devel, gcc-c++, zlib-devel
%{!?_without_freedesktop:BuildRequires: desktop-file-utils}


%description
Psi is the premiere Instant Messaging application designed for Microsoft Windows, 
Apple Mac OS X and GNU/Linux. Built upon an open protocol named Jabber,           
si is a fast and lightweight messaging client that utilises the best in open      
source technologies. The goal of the Psi project is to create a powerful, yet     
easy-to-use Jabber/XMPP client that tries to strictly adhere to the XMPP drafts.  
and Jabber JEPs. This means that in most cases, Psi will not implement a feature  
unless there is an accepted standard for it in the Jabber community. Doing so     
ensures that Psi will be compatible, stable, and predictable, both from an end-user 
and developer standpoint.
Psi+ - Psi IM Mod by psi-dev@conference.jabber.ru


%prep
%setup


%build
${qconfcmd}
./configure --prefix=\"%{_prefix}\" --libdir=\"%{_libdir}\" --bindir=\"%{_bindir}\" --datadir=\"%{_datadir}\" --qtdir=$QTDIR --enable-plugins ${iswebkit} ${no_enchant} --release --no-separate-debug-info
%{__make} %{?_smp_mflags}


%install
%{__rm} -rf %{buildroot}


%{__make} install INSTALL_ROOT=\"%{buildroot}\"


# Install the pixmap for the menu entry
%{__install} -Dp -m0644 iconsets/system/default/logo_128.png \
    %{buildroot}%{_datadir}/pixmaps/psi-plus.png ||:               

mkdir -p %{buildroot}%{_datadir}/psi-plus
mkdir -p %{buildroot}%{_bindir}
mkdir -p %{buildroot}%{_datadir}/applications

%post
touch --no-create %{_datadir}/icons/hicolor || :
%{_bindir}/gtk-update-icon-cache --quiet %{_datadir}/icons/hicolor || :


%postun
touch --no-create %{_datadir}/icons/hicolor || :
%{_bindir}/gtk-update-icon-cache --quiet %{_datadir}/icons/hicolor || :


%clean
%{__rm} -rf %{buildroot}


%files
%defattr(-, root, root, 0755)
%doc COPYING README TODO
%{_bindir}/psi-plus
#%{_bindir}/psi-plus.debug
%{_datadir}/psi-plus/
%{_datadir}/pixmaps/psi-plus.png
%{_datadir}/applications/psi-plus.desktop
%{_datadir}/icons/hicolor/*/apps/psi-plus.png
%exclude %{_datadir}/psi-plus/COPYING
%exclude %{_datadir}/psi-plus/README
"
  local tmp_spec=${buildpsi}/test.spec
  usr_spec=${rpmspec}/psi-plus.spec
  echo "${specfile}" > ${tmp_spec}
  cp -f ${tmp_spec} ${usr_spec}
}
#
build_rpm_package ()
{
  prepare_src
  prepare_tar
  local rev=$(cd ${buildpsi}/git-plus/; echo $(($(git describe --tags | cut -d - -f 2))))
  local tar_name=psi-plus-${psi_version}.${rev}
  local sources=${rpmsrc}
  if [ -f "${sources}/${tar_name}.tar.gz" ]; then
    prepare_spec
    echo "Building Psi+ RPM package"
    cd ${rpmspec}
    rpmbuild -ba --clean --rmspec --rmsource ${usr_spec}
    local rpm_ready=$(find $HOME/rpmbuild/RPMS | grep psi-plus)
    local rpm_src_ready=$(find $HOME/rpmbuild/SRPMS | grep psi-plus)
    cp -f ${rpm_ready} ${buildpsi}
    cp -f ${rpm_src_ready} ${buildpsi}
  fi
}
#
prepare_dev ()
{
  local psidev=$buildpsi/psidev
  local orig=$psidev/psi.orig
  local new=$psidev/psi
  rm -rf $orig
  rm -rf $new
  cd ${buildpsi}
  echo ${psidev}
  check_dir ${psidev}
  check_dir ${orig}
  check_dir ${new}
  if [ ! -d ${buildpsi}/git ]; then
    down_all
  fi
  cp -r git/* ${orig}
  cp -r git/* ${new}
  cd ${psidev}
  if [ ! -f deploy ]; then
    wget --no-check-certificate "https://raw.github.com/psi-plus/maintenance/master/scripts/posix/deploy" || die "Failed to update deploy";
  fi
  if [ ! -f mkpatch ]; then
    wget --no-check-certificate "https://raw.github.com/psi-plus/maintenance/master/scripts/posix/mkpatch" || die "Failed to update mkpatch";
    sed "s/maintenance\/scripts\/posix\/psidiff\.ignore/psidiff\.ignore/g" -i ${psidev}/mkpatch
  fi
  if [ ! -f psidiff.ignore ]; then
    wget --no-check-certificate "https://raw.github.com/psi-plus/maintenance/master/scripts/posix/psidiff.ignore" || die "Failed to update psidiff.ignore";
  fi
  local patchlist=$(ls ${buildpsi}/git-plus/patches/ | grep diff)
  cd ${orig}
  echo "---------------------
Patching original src
---------------------">${psidev}/patching.log
  echo -e "${blue}Enter maximum patch number to patch orig src${nocolor}"
  read patchnumber
  for patchfile in ${patchlist}; do
      if [  ${patchfile:0:4} -lt ${patchnumber} ]; then
        echo  "${patchfile}">>${psidev}/patching.log
        msg="${green}[OK]${nocolor}"
        patch -p1 --input=${buildpsi}/git-plus/patches/${patchfile} >>${psidev}/patching.log || msg="${red}[NO]${nocolor}"
        echo -e "${patchfile} ${msg}"
      fi
  done
  cd ${new}
  echo "---------------------
Patching work src
---------------------">>${psidev}/patching.log
  echo -e "${blue}Enter maximum patch number to patch work src${nocolor}"
  read patchnumber
  for patchfile in ${patchlist}; do
      if [  ${patchfile:0:4} -lt ${patchnumber} ]; then
        echo  "${patchfile}">>${psidev}/patching.log
        msg="${green}[OK]${nocolor}"
        patch -p1 --input=${buildpsi}/git-plus/patches/${patchfile} >>${psidev}/patching.log || msg="${red}[NO]${nocolor}"
        echo -e "${patchfile} ${msg}"
      fi
  done
}
#
prepare_plugins_spec ()
{
  local specfile="
Summary: ${summary}
Name: ${progname}
Version: ${rpmver}
Release: 1
License: GPL-2
Group: ${group}
URL: ${urlpath}
Source0: ${package_name}
BuildRequires: ${breq}
Requires: psi-plus
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-build

%description
${desc}

%prep
%setup

%build
cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=%{buildroot}%{_libdir} -DONLY_PLUGINS=ON -DPLUGINS_PATH=/psi-plus/plugins .
%{__make} %{?_smp_mflags} 

%install
[ \"%{buildroot}\" != \"/\"] && rm -rf %{buildroot}
%{__make} install INSTALL_ROOT=\"%{buildroot}\"

if [ \"%{_target_cpu}\" = \"x86_64\" ] && [ -d \"/usr/lib64\" ]; then
  mkdir -p %{buildroot}/usr/lib64
else
  mkdir -p %{buildroot}/usr/lib
fi

%clean
[ \"%{buildroot}\" != \"/\" ] && rm -rf %{buildroot}

%files
%{_libdir}/psi-plus/plugins
"
  echo "${specfile}" > ${rpmspec}/${progname}.spec
}
#
build_rpm_plugins ()
{
  local progname="psi-plus-plugins"
  fetch_cmake_files
  prepare_src
  check_dir ${orig_src}
  cp -rf ${cmake_files_dir}/* ${orig_src}/
  cd ${buildpsi}
  local rev=$(cd ${buildpsi}/git-plus/; echo $(($(git describe --tags | cut -d - -f 2))))
  local rpmver=${psi_version}.${rev}
  local allpluginsdir=${buildpsi}/${progname}-${rpmver}
  local package_name="${progname}-${rpmver}.tar.gz"
  local summary="Plugins for psi-plus-${rpmver}"
  local breq="libotr2-devel, libtidy-devel, libgcrypt-devel, libgpg-error-devel"
  local urlpath="https://github.com/psi-plus/plugins"
  local group="Applications/Internet"
  local desc="Plugins for jabber-client Psi+"
  check_dir ${allpluginsdir}
  cp -r ${orig_src}/* ${allpluginsdir}/
  cd ${buildpsi}
  tar -pczf $package_name ${progname}-${rpmver}
  prepare_plugins_spec
  cp -rf ${package_name} ${rpmsrc}/
  rpmbuild -ba --clean --rmspec --rmsource ${rpmspec}/${progname}.spec
  echo "Cleaning..."
  cd ${buildpsi}
  rm -rf ${allpluginsdir}
}
#
get_resources ()
{
  cd ${buildpsi}
  git clone git://github.com/psi-plus/resources.git
}
#
install_resources ()
{
  cd ${buildpsi}
  check_dir ${psi_datadir}
  if [ ! -d "resources" ]; then
    get_resources
  fi
  cp -rf ${buildpsi}/resources/* ${psi_datadir}/
}
#
install_iconsets ()
{
  cd ${buildpsi}
  check_dir ${psi_datadir}
  if [ -d "resources" ]; then
    get_resources
  fi  
  cp -rf ${buildpsi}/resources/iconsets ${psi_datadir}/
}
#
install_skins ()
{
  cd ${buildpsi}
  check_dir ${psi_datadir}
  if [ -d "resources" ]; then
    cp -rf ${buildpsi}/resources/skins ${psi_datadir}/
  else
    get_resources
    cp -rf ${buildpsi}/resources/skins ${psi_datadir}/
  fi 
}
#
install_sounds ()
{
  cd ${buildpsi}
  check_dir ${psi_datadir}
  if [ -d "resources" ]; then
    cp -rf ${buildpsi}/resources/sound ${psi_datadir}/
  else
    get_resources
    cp -rf ${buildpsi}/resources/sound ${psi_datadir}/
  fi 
}
#
install_themes ()
{
  cd ${buildpsi}
  check_dir ${psi_datadir}
  if [ -d "resources" ]; then
    cp -rf ${buildpsi}/resources/themes ${psi_datadir}/
  else
    get_resources
    cp -rf ${buildpsi}/resources/themes ${psi_datadir}/
  fi 
}
#
update_resources ()
{
  cd ${buildpsi}/resources
  git pull
}
#
build_locales ()
{
  local tr_path=${buildpsi}/langs/translations
  run_libpsibuild fetch_sources
  if [ -d "${tr_path}" ]; then
    rm -f ${tr_path}/*.qm
    if [ -f "/usr/bin/lrelease" ] || [ -f "/usr/local/bin/lrelease" ]; then
      lrelease ${tr_path}/*.ts 
    fi
    if [ -f "/usr/bin/lrelease-qt4" ] || [ -f "/usr/local/bin/lrelease-qt4" ]; then
      lrelease-qt4 ${tr_path}/*.ts 
    fi
  fi 
}
#
install_locales ()
{
  local tr_path=${buildpsi}/langs/translations
  build_locales
  check_dir ${psi_datadir}
  cp -rf ${tr_path}/*.qm ${psi_datadir}/
}
#
set_config ()
{
  local use_webkit="n"
  if [ ! -z "$iswebkit" ]; then
    use_webkit="y"
  else
    use_webkit="n"
  fi
  local is_offline="n"
  if [ "$isoffline" -eq 0 ]; then
    is_offline="n"
  else
    is_offline="y"
  fi
  local skip_patches="n"
  if [ "$skip_invalid" -eq 0 ]; then
    skip_patches="n"
  else
    skip_patches="y"
  fi
  local noenchant="y"
  if [ ! -z "${no_enchant}" ]; then
    noenchant="y"
  else
    noenchant="n"
  fi
  local loop=1
  while [ ${loop} = 1 ];  do
    echo -e "${blue}Choose action TODO:${nocolor}
--${pink}[1]${nocolor} - Set WebKit version to use (current: ${use_webkit})
--${pink}[2]${nocolor} - Set iconsets list needed to build
--${pink}[3]${nocolor} - Set Offline Mode (current: ${is_offline})
--${pink}[4]${nocolor} - Skip Invalid patches (current: ${skip_patches})
--${pink}[5]${nocolor} - Set list of plugins needed to build (for all use *)
--${pink}[6]${nocolor} - Set use aspell instead of enchant (current: ${noenchant})
--${pink}[7]${nocolor} - Set psi+ sources path (current: ${buildpsi})
--${pink}[8]${nocolor} - Print option values
--${pink}[0]${nocolor} - Do nothing"
    read deistvo
    case ${deistvo} in
      "1" ) echo -e "Do you want use WebKit ${pink}[y/n]${nocolor} ?"
            read variable
            if [ "$variable" == "y" ]; then
              iswebkit="--enable-webkit"
              use_webkit="y"
            else
              iswebkit=""
              use_webkit="n"
            fi;;
      "2" ) echo "Please enter iconsets separated by space"
            read variable
            if [ ! -z "$variable" ]; then
              use_iconsets=${variable}
            else
              use_iconsets="system clients activities moods affiliations roster"
            fi;;
      "3" ) echo -e "Do you want use Offline Mode ${pink}[y/n]${nocolor} ?"
            read variable
            if [ "$variable" == "y" ]; then
              isoffline=1
              is_offline="y"
            else
              isoffline=0
              is_offline="n"
            fi;;
      "4" ) echo -e "Do you want to skip invalid patches when patching ${pink}[y/n]${nocolor} ?"
            read variable
            if [ "$variable" == "y" ]; then
              skip_invalid=1
              skip_patches="y"
            else
              skip_invalid=0
              skip_patches="n"
            fi;;
      "5" ) echo "Please enter plugins needed to build separated by space (* for all)"
            read variable
            if [ ! -z "$variable" ]; then
              use_plugins=${variable}
            else
              use_plugins=""
            fi;;
      "6" ) echo -e "Do you want use aspell spellcheck engine instead on enchant ${pink}[y/n]${nocolor} ?"
            read variable
            if [ "$variable" == "y" ]; then
              no_enchant="--disable-enchant"
            else
              no_enchant=""
            fi;;
      "7" ) echo "Please set psi+ sources path (absolute path, or \$HOME/path)"
            read variable
            if [ ! -z "${variable}" ]; then
              if [ "${variable:0:5}" == "\$HOME" ]; then
                buildpsi=${home}/${variable:6}
              else
                buildpsi=${variable}
              fi
            else
              buildpsi=${default_buildpsi}
            fi;;            
      "8" ) echo -e "${blue}==Options==${nocolor}
${green}WebKit${nocolor} = ${yellow}${use_webkit}${nocolor}
${green}Iconsets${nocolor} = ${yellow}${use_iconsets}${nocolor}
${green}Offline Mode${nocolor} = ${yellow}${is_offline}${nocolor}
${green}Skip Invalid Patches${nocolor} = ${yellow}${skip_patches}${nocolor}
${green}Plugins${nocolor} = ${yellow}${use_plugins}${nocolor}
${green}No Enchant${nocolor} = ${yellow}${noenchant}${nocolor}
${green}Psi+ sources path${nocolor} = ${yellow}${buildpsi}${nocolor}
${blue}===========${nocolor}";;
      "0" ) clear
            loop=0;;
    esac
  done
  echo "$iswebkit" > ${config_file}
  echo "$use_iconsets" >> ${config_file}
  echo "$isoffline" >> ${config_file}
  echo "$skip_invalid" >> ${config_file}
  if [ "$use_plugins" == "*" ]; then
    echo "all" >> ${config_file}
  else
    echo "$use_plugins" >> ${config_file}
  fi
  echo "$no_enchant" >> ${config_file}
  echo "$buildpsi" >> ${config_file}
  update_variables
}
#
print_menu ()
{
  echo -e "${blue}Choose action TODO!${nocolor}
${pink}[1]${nocolor} - Download All needed source files to build psi+
${pink}[2]${nocolor} - Prepare psi+ sources
${pink}[3]${nocolor} - Build psi+ binary
---${pink}[31]${nocolor} - Build and install psi+ plugins
${pink}[4]${nocolor} - Build Debian package with checkinstall
${pink}[5]${nocolor} - Build openSUSE RPM-package
---${pink}[51]${nocolor} - Build plugins openSUSE RPM-package
${pink}[6]${nocolor} - Set libpsibuild options
${pink}[7]${nocolor} - Prepare psi+ sources for development
${pink}[8]${nocolor} - Build psi+ plugins using CMAKE
${pink}[9]${nocolor} - Get help on additional actions
${pink}[0]${nocolor} - Exit"
}
#
get_help ()
{
  echo -e "${red}---------------HELP-----------------------${nocolor}
${pink}[ia]${nocolor} - Install all resources to $psi_datadir
${pink}[ii]${nocolor} - Install iconsets to $psi_datadir
${pink}[is]${nocolor} - Install skins to $psi_datadir
${pink}[iz]${nocolor} - Install sounds to to $psi_datadir
${pink}[it]${nocolor} - Install themes to $psi_datadir
${pink}[il]${nocolor} - Install locales to $psi_datadir
${pink}[bl]${nocolor} - Just build locale files without installing
${pink}[ba]${nocolor} - Download all sources and build psi+ binary with plugins
${pink}[ur]${nocolor} - Update resources
${pink}[bs]${nocolor} - Backup ${buildpsi##*/} directory in ${buildpsi%/*}
${pink}[pw]${nocolor} - Prepare psi+ workspace (clean ${buildpsi}/build dir)
${red}-------------------------------------------${nocolor}
${blue}Press Enter to continue...${nocolor}"
  read
}
#
choose_action ()
{
  set_options
  read vibor
  case ${vibor} in
    "1" ) down_all;;
    "2" ) prepare_src;;
    "3" ) compile_psiplus;;
    "31" ) build_plugins;;
    "4" ) build_deb_package;;
    "5" ) build_rpm_package;;
    "51" ) build_rpm_plugins;;
    "6" ) set_config;;
    "7" ) prepare_dev;;
    "9" ) get_help;;
    "ia" ) install_resources;;
    "ii" ) install_iconsets;;
    "is" ) install_skins;;
    "iz" ) install_sounds;;
    "it" ) install_themes;;
    "ur" ) update_resources;;
    "ba" ) compile_psiplus
           build_plugins;;
    "il" ) install_locales;;
    "bl" ) build_locales;;
    "bs" ) backup_tar;;
    "pw" ) run_libpsibuild prepare_workspace;;
    "8" ) build_cmake_plugins;;
    "0" ) quit;;
  esac
}
#
cd ${workdir}
read_options
check_libpsibuild
if [ ! -f "${config_file}" ]; then
  set_config
fi
find_qconf
find_ccache
set_options
clear
#
while true; do
  print_menu
  choose_action
done
exit 0
