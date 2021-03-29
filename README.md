### Known Problems

* On Ubuntu 18, when reporting missing libmpfr.so.4, seems there is no full solution but a workaround
~~~bash
sudo ln -s /usr/lib/x86_64-linux-gnu/libmpfr.so.6 /usr/lib/x86_64-linux-gnu/libmpfr.so.4
~~~
