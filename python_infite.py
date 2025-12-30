import argparse
import random
import sys
import os
import json

# Try to import required libraries
try:
    import numpy as np
    import librosa
    import soundfile as sf
except ImportError as e:
    print(f"Error: Missing dependency. {e}")
    print("Please install the required libraries:")
    print("pip install numpy librosa soundfile")
    sys.exit(1)

# Configuration weights from Eternal Jukebox (go-js.html)
WEIGHTS = {
    'timbre': 1,
    'pitch': 10,
    'loudness_start': 1,
    'loudness_max': 1,
    'duration': 100,
    'confidence': 1
}

def analyze_audio(file_path):
    """
    Analyzes the audio file to extract beats and features.
    """
    print(f"Analyzing {file_path}...")
    try:
        y, sr = librosa.load(file_path)
    except Exception as e:
        print(f"Error loading audio file: {e}")
        sys.exit(1)

    # Extract beats
    # Use librosa's beat tracker
    tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr)
    beat_times = librosa.frames_to_time(beat_frames, sr=sr)

    # We need features synchronized to beats.
    # Eternal Jukebox uses:
    # - Timbre (12-dim vector, likely MFCC-like or PCA of spectrum)
    # - Pitches (12-dim Chroma vector)
    # - Loudness Start & Max (dB)
    # - Duration
    # - Confidence

    # 1. MFCC for Timbre (12 coefficients to match typical Spotify analysis)
    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=12)

    # 2. Chroma for Pitches
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr)

    # 3. Loudness (RMS converted to dB)
    S, phase = librosa.magphase(librosa.stft(y))
    rms = librosa.feature.rms(S=S)
    loudness_db = librosa.amplitude_to_db(rms, ref=np.max)

    # Synchronize features to beats
    # aggregate_features will take the mean of features between beat frames
    # beat_frames indices correspond to the spectrogram frames

    # We need to ensure we cover the whole song, so we might need to add start/end frames if beat_track doesn't
    # beat_track returns frames of detected beats.

    # librosa.util.sync synchronizes a feature matrix to beat frames
    # It computes the aggregate (default mean) feature value between beat boundaries.

    # Note: beat_frames usually marks the *center* or *onset* of the beat.
    # For segmentation, we want intervals.
    # librosa.util.sync uses the beat frames as boundaries for aggregation.

    mfcc_sync = librosa.util.sync(mfcc, beat_frames)
    chroma_sync = librosa.util.sync(chroma, beat_frames)
    loudness_sync = librosa.util.sync(loudness_db, beat_frames)

    beats = []
    # beat_times corresponds to the time of the beat markers.
    # We can treat the interval between beat_times[i] and beat_times[i+1] as the segment/quantum.

    # However, sync returns N columns for N+1 boundaries? Or N boundaries?
    # Documentation says: "beat_frames : ... frame indices of beat events"
    # "aggregate_features is of shape (d, len(beat_frames))" if we assume beat_frames are centers?
    # Actually librosa.util.sync treats them as boundaries if you pass them right,
    # but strictly it "aggregates features between beat events".
    # Result shape is (n_features, n_beats).

    num_beats = mfcc_sync.shape[1]

    # We need to handle the time segments carefully.
    # The beat_times array has the timestamps of the beats.
    # Let's assume the i-th column of sync features corresponds to the interval starting at beat_times[i].
    # But we need duration.

    for i in range(num_beats):
        if i >= len(beat_times) - 1:
            # Last beat, estimating duration from previous or until end of file
            # If beat_times covers until end, good. If not, we approximate.
            # beat_track usually doesn't include 0.0 or the very end unless a beat is there.
            continue

        start = beat_times[i]
        end = beat_times[i+1]
        duration = end - start

        # Features
        timbre = mfcc_sync[:, i]
        pitch = chroma_sync[:, i]

        # Loudness
        # We need start and max.
        # sync gives average (or whatever func).
        # Let's just use the average for both or try to be more precise if we had raw frames.
        # For this script, using the synchronized average for both is a simplification.
        l_val = loudness_sync[0, i]

        beats.append({
            'index': i,
            'start': start,
            'duration': duration,
            'timbre': timbre,
            'pitch': pitch,
            'loudness_max': l_val,
            'loudness_start': l_val, # Approximation
            'confidence': 1.0, # Approximation
            'neighbors': []
        })

    return y, sr, beats

def euclidean_distance(v1, v2):
    return np.linalg.norm(v1 - v2)

def get_seg_distances(seg1, seg2):
    """
    Calculates the weighted distance between two segments.
    """
    timbre = euclidean_distance(seg1['timbre'], seg2['timbre'])
    pitch = euclidean_distance(seg1['pitch'], seg2['pitch'])
    sloudStart = abs(seg1['loudness_start'] - seg2['loudness_start'])
    sloudMax = abs(seg1['loudness_max'] - seg2['loudness_max'])
    duration = abs(seg1['duration'] - seg2['duration'])
    confidence = abs(seg1['confidence'] - seg2['confidence'])

    distance = (timbre * WEIGHTS['timbre'] +
                pitch * WEIGHTS['pitch'] +
                sloudStart * WEIGHTS['loudness_start'] +
                sloudMax * WEIGHTS['loudness_max'] +
                duration * WEIGHTS['duration'] +
                confidence * WEIGHTS['confidence'])
    return distance

def generate_graph(beats, threshold):
    """
    Connects beats based on similarity.
    """
    print(f"Generating graph with threshold {threshold}...")
    edge_count = 0

    for i, b1 in enumerate(beats):
        for j, b2 in enumerate(beats):
            if i == j:
                continue

            # Simple distance calculation (pairwise)
            # In the JS code, it sums distances of overlapping segments for beats.
            # Here we simplified beats to be the segments themselves.
            dist = get_seg_distances(b1, b2)

            # JS adds a penalty if indexInParent is different (beat position in bar)
            # We don't have bar analysis here easily, so we skip that or could approximate with beat % 4.
            # let's skip for now or add small penalty if absolute beat index % 4 is different?
            # if (b1['index'] % 4) != (b2['index'] % 4):
            #    dist += 100 # This would be huge. JS adds 100 if phase doesn't match?
            #    "var pdistance = q1.indexInParent == q2.indexInParent ? 0 : 100;"
            #    Yes, it enforces rhythmic structure.

            # Let's try to enforce simple 4/4 assumption for rhythm continuity
            if (b1['index'] % 4) != (b2['index'] % 4):
                dist += 100

            if dist < threshold:
                b1['neighbors'].append({
                    'dest': j,
                    'distance': dist
                })
                edge_count += 1

    print(f"Created {edge_count} edges.")
    return beats

def generate_infinite_track(y, sr, beats, duration_minutes, branch_probability, output_path):
    """
    Generates the infinite track by following the graph.
    """
    print(f"Generating {duration_minutes} minutes of audio...")

    target_samples = int(duration_minutes * 60 * sr)
    generated_samples = 0

    output_segments = []

    current_index = 0

    while generated_samples < target_samples:
        if current_index >= len(beats):
            current_index = 0

        beat = beats[current_index]

        # Get audio segment
        start_sample = int(beat['start'] * sr)
        end_sample = int((beat['start'] + beat['duration']) * sr)

        # Append audio
        segment = y[start_sample:end_sample]
        output_segments.append(segment)
        generated_samples += len(segment)

        # Decide next beat
        neighbors = beat['neighbors']

        # Sort neighbors by distance to prefer better matches?
        # JS logic picks one if available and chance is met.

        jumped = False
        if neighbors and random.random() < branch_probability:
            # Pick a random neighbor? Or weighted?
            # Let's pick uniformly from neighbors for variety
            next_beat = random.choice(neighbors)
            current_index = next_beat['dest']
            jumped = True

        if not jumped:
            current_index += 1

    # Concatenate and save
    print("Concatenating audio...")
    full_audio = np.concatenate(output_segments)

    # Trim if needed (though we just stopped loop)
    if len(full_audio) > target_samples:
        full_audio = full_audio[:target_samples]

    print(f"Saving to {output_path}...")
    sf.write(output_path, full_audio, sr)
    print("Done!")

def main():
    parser = argparse.ArgumentParser(description='Generate an infinite version of a song (Eternal Jukebox style).')
    parser.add_argument('input_file', type=str, help='Path to the input audio file')
    parser.add_argument('--output', type=str, default='infinite.wav', help='Path to the output audio file')
    parser.add_argument('--duration', type=float, default=5.0, help='Target duration in minutes')
    parser.add_argument('--threshold', type=float, default=60.0, help='Similarity threshold (lower is stricter). Default 60.')
    parser.add_argument('--prob', type=float, default=0.5, help='Branch probability (0.0 to 1.0). Default 0.5.')

    args = parser.parse_args()

    if not os.path.exists(args.input_file):
        print(f"File not found: {args.input_file}")
        sys.exit(1)

    y, sr, beats = analyze_audio(args.input_file)
    beats = generate_graph(beats, args.threshold)

    generate_infinite_track(y, sr, beats, args.duration, args.prob, args.output)

if __name__ == "__main__":
    main()
