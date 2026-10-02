from PIL import Image
im = Image.open('/tmp/dock5.png')
w, h = im.size
im.crop((int(w*0.25), h-90, int(w*0.75), h)).save('/tmp/dockzoom.png')
print('cropped', im.size)
