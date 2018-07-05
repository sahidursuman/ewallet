FROM omisegoimages/ewallet-runtime:beec6e8

LABEL maintainer="OmiseGO Team <omg@omise.co>"
LABEL description="Official image for OmiseGO eWallet"

ADD ewallet.tar.gz /app
RUN chown -R ewallet:ewallet /app
WORKDIR /app

ENV PORT 4000

EXPOSE 4000
EXPOSE 4369
EXPOSE 6900 6901 6902 6903 6904 6905 6906 6907 6908 6909

COPY rootfs /