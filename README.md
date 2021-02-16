# AIDrivers

This is a Swift port of the [original C implementation](https://gist.github.com/skeeto/da7b2ac95730aa767c8faf8ec309815c) by Christopher Wellons. For more, read Christopher's blog post titled [You might not need machine learning](https://nullprogram.com/blog/2020/11/24/).

For best performance, compile the binary in release mode first:

    $ swift build -c release

When you run the binary, it'll read the map file in PPM format from standard input and write the output video as a series of PPM files which can be piped into a program like `ffmpeg` to generate a video file: 

    $ .build/release/AIDrivers < map.ppm | ffmpeg -y -r 60 -i - -r 60 -t 60 -c:v libx264 -pix_fmt yuv420p out.mp4

This will generate a video file called `out.mp4` demonstrating the performance of vehicles with different driving characteristics.
