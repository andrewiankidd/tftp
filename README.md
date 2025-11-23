# andrewkidd/tftp-server

![image representing tftp](.github/workflows/logo.png)

TFTP running in an alpine container, built for ARM and X86

This is a fork of [pghalliday-docker/tftp](https://github.com/pghalliday-docker/tftp) with some minor updates. Original credit goes there.

## Building

### Locally
Build directly from the `src` context:

```sh
docker build -f src/Dockerfile ./src -t andrewkidd/tftp-server:local
```


### GitHub WorkFlow

GitHub will build and publish linux/amd64 and linux/arm64 images automatically when the pre-requisites are met.

This process is defined in
`.github/workflows/docker-multiarch.yml`.

#### Pre-requisites
 - Triggers: Changes made to `src` files
 - Tag: Commit must be tagged with `v*`
 - Secrets: The following must be defined in your GitHub project 
   - DOCKERHUB_REPO
   - DOCKERHUB_USERNAME
   - DOCKERHUB_TOKEN 

## Running

### Docker
Example host-network run with a bind-mounted TFTP root:

```sh
docker run -d --name tftp-server --network host \
  -e HOSTNETWORK=true \
  -e TFTPD_LISTEN=true \
  -e TFTPD_ADDRESS=0.0.0.0:69 \
  -e TFTPD_PORT_RANGE=5000:5010 \
  -v /path/to/tftpboot:/var/tftpboot \
  andrewkidd/tftp-server:latest
```

### Docker Compose
```
services:
  netboot-tftp:
    image: andrewkidd/tftp-server
    container_name: netboot-tftp
    network_mode: host
    environment:
      HOSTNETWORK: "true"
      TFTPD_LISTEN: "true"
      TFTPD_ADDRESS: "0.0.0.0:69"
      TFTPD_DEBUG: "true"
      TFTPD_PORT_RANGE: "5000:5010"
      TFTPD_FOREGROUND: "true"
      TFTPD_VERBOSE_COUNT: "5"
      TFTPD_VERBOSITY: "8"
      TFTPD_SECURE_MODE: "true"
      TFTPD_DIRECTORIES: "/var/tftpboot"
    volumes:
      - ./README.md:/var/tftpboot/test.txt:ro
      - netboot-boot-data:/var/tftpboot
    ports:
      - 69:69/udp
      - 5000:5000/udp
      - 5001:5001/udp
      - 5002:5002/udp
      - 5003:5003/udp
      - 5004:5004/udp
      - 5005:5005/udp
      - 5006:5006/udp
      - 5007:5007/udp
      - 5008:5008/udp
      - 5009:5009/udp
      - 5010:5010/udp
    healthcheck:
      test: ["CMD", "test", "-f", "/var/tftpboot/test.txt"]
      interval: 1m
      timeout: 5s
      retries: 0
      start_period: 1m
    restart: unless-stopped

volumes:
  netboot-boot-data:
```

### Kubernetes

```
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: tftp
spec:
  selector:
    matchLabels:
      app: netboot
      component: tftp
  template:
    metadata:
      labels:
        app: netboot
        component: tftp
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      containers:
        - name: tftp
          image: andrewkidd/tftp-server
          imagePullPolicy: IfNotPresent
          env:
            - name: HOSTNETWORK
              value: "true"
            - name: TFTPD_LISTEN
              value: "true"
            - name: TFTPD_ADDRESS
              value: "0.0.0.0:69"
            - name: TFTPD_DEBUG
              value: "true"
            - name: TFTPD_PORT_RANGE
              value: "5000:5010"
            - name: TFTPD_FOREGROUND
              value: "true"
            - name: TFTPD_VERBOSE_COUNT
              value: "5"
            - name: TFTPD_VERBOSITY
              value: "8"
            - name: TFTPD_SECURE_MODE
              value: "true"
            - name: TFTPD_DIRECTORIES
              value: "/var/tftpboot"

          ports:
            - name: tftp
              containerPort: 69
              hostPort: 69
              protocol: UDP
            - name: tftp-data
              containerPort: 5000
              hostPort: 5000
              protocol: UDP
            - name: tftp-data2
              containerPort: 5001
              hostPort: 5001
              protocol: UDP
            - name: tftp-data3
              containerPort: 5002
              hostPort: 5002
              protocol: UDP
            - name: tftp-data4
              containerPort: 5003
              hostPort: 5003
              protocol: UDP
            - name: tftp-data5
              containerPort: 5004
              hostPort: 5004
              protocol: UDP
            - name: tftp-data6
              containerPort: 5005
              hostPort: 5005
              protocol: UDP
            - name: tftp-data7
              containerPort: 5006
              hostPort: 5006
              protocol: UDP
            - name: tftp-data8
              containerPort: 5007
              hostPort: 5007
              protocol: UDP
            - name: tftp-data9
              containerPort: 5008
              hostPort: 5008
              protocol: UDP
            - name: tftp-data10
              containerPort: 5009
              hostPort: 5009
              protocol: UDP
            - name: tftp-data11
              containerPort: 5010
              hostPort: 5010
              protocol: UDP
          volumeMounts:
            - name: boot
              mountPath: /var/tftpboot
      volumes:
        - name: boot
          persistentVolumeClaim:
            claimName: netboot-boot
```

## Acknowledgments

- Forked from [pghalliday-docker/tftp](https://github.com/pghalliday-docker/tftp)
- Inspired by [3x3cut0r/tftpd-hpa](https://github.com/3x3cut0r/docker/tree/main/tftpd-hpa)
- Built for [andrewkidd/project-iluvatar](https://github.com/andrewiankidd/project-iluvatar)
- Logo generated by [ChatGPT GPT 5.1](https://chatgpt.com)
- Logo background removed with [removebg](https://www.remove.bg/)