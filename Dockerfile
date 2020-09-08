ARG TF_SET_VERSION=1.5.1
ARG ROS_SET_VERSION=kinetic
ARG UBUNTU_SET_VERSION=xenial
# Build libglvnd
FROM ubuntu:14.04 as glvnd

RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        ca-certificates \
        make \
        automake \
        autoconf \
        libtool \
        pkg-config \
        python \
        libxext-dev \
        libx11-dev \
        x11proto-gl-dev && \
    rm -rf /var/lib/apt/lists/*

ARG LIBGLVND_VERSION=v1.1.0

WORKDIR /opt/libglvnd
RUN git clone --branch="${LIBGLVND_VERSION}" https://github.com/NVIDIA/libglvnd.git . && \
    ./autogen.sh && \
    ./configure --prefix=/usr/local --libdir=/usr/local/lib/x86_64-linux-gnu && \
    make -j"$(nproc)" install-strip && \
    find /usr/local/lib/x86_64-linux-gnu -type f -name 'lib*.la' -delete

RUN dpkg --add-architecture i386 && \
    apt-get update && apt-get install -y --no-install-recommends \
        gcc-multilib \
        libxext-dev:i386 \
        libx11-dev:i386 && \
    rm -rf /var/lib/apt/lists/*

# 32-bit libraries
RUN make distclean && \
    ./autogen.sh && \
    ./configure --prefix=/usr/local --libdir=/usr/local/lib/i386-linux-gnu --host=i386-linux-gnu "CFLAGS=-m32" "CXXFLAGS=-m32" "LDFLAGS=-m32" && \
    make -j"$(nproc)" install-strip && \
    find /usr/local/lib/i386-linux-gnu -type f -name 'lib*.la' -delete

ARG TF_SET_VERSION
ARG ROS_SET_VERSION
ARG UBUNTU_SET_VERSION
FROM ros-tensorflow:$ROS_SET_VERSION-tf$TF_SET_VERSION
LABEL maintainer "NVIDIA CORPORATION <cudatools@nvidia.com>"

COPY --from=glvnd /usr/local/lib/x86_64-linux-gnu /usr/local/lib/x86_64-linux-gnu
COPY --from=glvnd /usr/local/lib/i386-linux-gnu /usr/local/lib/i386-linux-gnu

COPY 10_nvidia.json /usr/local/share/glvnd/egl_vendor.d/10_nvidia.json

RUN echo '/usr/local/lib/x86_64-linux-gnu' >> /etc/ld.so.conf.d/glvnd.conf && \
    echo '/usr/local/lib/i386-linux-gnu' >> /etc/ld.so.conf.d/glvnd.conf && \
    ldconfig

ENV LD_LIBRARY_PATH /usr/local/lib/x86_64-linux-gnu:/usr/local/lib/i386-linux-gnu${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
ARG TF_SET_VERSION
ARG ROS_SET_VERSION
ARG UBUNTU_SET_VERSION

# maskgraph
# generic tools
ENV UBUNTU_VERSION $UBUNTU_SET_VERSION

ENV ROS_VERSION $ROS_SET_VERSION

RUN apt update && apt install python-catkin-tools wget -y

RUN apt install autoconf -y

RUN apt install curl -y

RUN apt install libtool -y

RUN apt install ros-${ROS_VERSION}-geometry ros-${ROS_VERSION}-rviz -y

# add user
ARG myuser
ARG USERNAME=$myuser
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && apt-get update \
    && apt-get install -y sudo \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME
RUN usermod -a -G dialout $myuser

RUN apt install libblas-dev liblapack-dev -y

# nvidia-container-runtime
ENV NVIDIA_VISIBLE_DEVICES \
    ${NVIDIA_VISIBLE_DEVICES:-all}
ENV NVIDIA_DRIVER_CAPABILITIES \
    ${NVIDIA_DRIVER_CAPABILITIES:+$NVIDIA_DRIVER_CAPABILITIES,}graphics

RUN apt-get update && apt-get install -y \
    mesa-utils && \
    rm -rf /var/lib/apt/lists/*

RUN apt update && apt install ros-${ROS_VERSION}-rgbd-launch -y

RUN apt update && apt install libtbb-dev -y

RUN git clone https://github.com/OpenKinect/libfreenect2.git
RUN cd libfreenect2/depends && ./download_debs_trusty.sh && dpkg -i debs/libusb*deb && dpkg -i debs/libglfw3*deb && apt-get install -f
RUN apt-get install build-essential cmake pkg-config -y
RUN apt-get install libturbojpeg libjpeg-turbo8-dev -y
RUN apt-get install libopenni2-dev -y

RUN cd libfreenect2 && mkdir build && cd build && cmake .. -DENABLE_CXX11=ON && make && make install
RUN cd libfreenect2 && cp platform/linux/udev/90-kinect2.rules /etc/udev/rules.d/

RUN apt update && apt install ros-${ROS_VERSION}-image-pipeline ros-${ROS_VERSION}-image-transport-plugins ros-${ROS_VERSION}-image-transport ros-${ROS_VERSION}-nodelet-core -y

# install and config ccache
#RUN apt install ccache -y
#ENV PATH "/usr/lib/ccache:$PATH"
#RUN ccache --max-size=10G

ENTRYPOINT [ "/ros_entrypoint.sh" ]
CMD [ "bash" ]
