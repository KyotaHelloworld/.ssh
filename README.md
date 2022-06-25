# ssh setting directory

## installation
1. backup .ssh directory and clone
```sh
ls ~.ssh && mv ~/.ssh ~/.ssh.bk
git clone https://github.com/KyotaHelloworld/.ssh.git ~/.ssh
```
1. put keys created before onto `~/.ssh/keys/`


## private key
- *! ! ! caution* ***DO NOT track, commit and push Your Private Keys*** 

- when create new key, use make command.
    - add dash(-) and service name.
    ```sh
    make new-key-ServiceName
    ```
    - example for creating github key
    ```sh
    make new-key-github 
    ```
    - `$ make` prints help.
- for your privacy safe, use ed25519 key.
    - make commands use ed25519 as default.
    - use `CT` param to change key type
    ```sh
    make CT=rsa new-key-github
    ```
- key file is basically named `id` & `id.pub`.
    - you can change file name using `FN` param.
    ```sh
    make FN=ed25519.id new-key-github
    ```
- key file is located at `~/.ssh/keys/[ServiceName]/id`

## config file
- config files are stored in `~/.ssh/config.d/`.
    - a file include *private* in the name will be not tracking.

